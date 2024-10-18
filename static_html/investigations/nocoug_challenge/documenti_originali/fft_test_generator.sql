
drop table fft_test;

create table fft_test (
  N                 int    not null,
  s                 int    not null,
  probability       number not null,
  probability_exact number,
  constraint fft_test_pk primary key (N,s)
);

drop table fft_perf;

create table fft_perf (N int not null, millis int not null);

create or replace procedure fft_test_p (
  p_min_N       int, 
  p_max_N       int, 
  p_step_N_lin  int default 1, 
  p_step_N_geom int default 0)
is
  l_stmt long;
  l_time_start number;
  l_time_end number;
  N number;
begin
  l_stmt 
  := 'insert into fft_test (N, s, probability, probability_exact)'
  || ' select :N, s, probability, null'
  || ' from ('
  || q'|  
with die_ieee as (
  -- the die casted using IEEE 754 arithmetic
  select cast (face_value  as binary_double) as face_value,
         cast (probability as binary_double) as probability
    from die
), base_constants as (  
  -- Calculate max_s_1, the highest s for which P(s,1) is > 0,
  -- that is, the max face value of the die_ieee
  select max (face_value) as max_s_1  
    from die_ieee 
   where probability != 0
), derived_constants as (
  -- Calculate max_s_N, the highest s for which P(s,N) is > 0, which is (:N * max_s_1):
  -- for example, max_s_1=8, after 3 throws the max s observed will be 8*3=24.
  -- Hence we need to calculate P(s,N) over the range 0 .. max_s_N,
  -- that is, we need to calculate the FT over max_s_N * :N + 1 values.
  -- Since the Cooley-Tukey FFT variant needs to operate on vectors whose size
  -- is an exact power of two, we calculate and store in log_vector_size the
  -- logarithm of the smallest such power of two.
  select max_s_1,
         max_s_1 * cast (:N as binary_double) as max_s_N,
         ceil ( log (2D, max_s_1 * cast (:N as binary_double) + 1D) ) as log_vector_size
    from base_constants
), constants as (
  -- add vector_size=2^log_vector_size and the useful PI constant
  select log_vector_size,
         power (2D, log_vector_size) as vector_size,
         3.14159265358979323846264338327950288419716939937510D as PI
    from derived_constants
), s_sequence as (
  -- build the sequence of all possible s values: 0..vector_size
  -- this is of course the number of frequencies as well
  select cast (rownum-1 as binary_double) as s from dual connect by level <= (select vector_size from constants)
), p_s_1 as (
  -- set P(s,1) over all possible values of s (zero for non-existent face value) 
  select s, nvl (die_ieee.probability, 0) as probability
    from s_sequence, die_ieee
   where s_sequence.s = die_ieee.face_value(+)
     and die_ieee.probability(+) != 0D
), dft_p_s_1 as (
  -- calculate DFT [ P(s,1) ] using Cooley-Tukey decimation-in-frequency
  -- NB: outputs are scrambled in bit-reversal order
  -- see http://www.cmlab.csie.ntu.edu.tw/cml/dsp/training/coding/transform/fft.html
  select f, real, imag
    from (select s as f, probability as real, 0D as imag from p_s_1)
  model
    -- lookup tables for constants (import constants inside the model)
    reference constants on (select 0D dummy, c.* from constants c)
      dimension by (dummy)
      measures (log_vector_size)
    -- lookup table for butterfly parameters, indexed by iteration_number
    -- the "width" is how much the butterfly wings are "open"
    -- the "w_expon" is the component of the exponent of W that varies with
    -- each iteration
    reference butterfly on (select cast (rownum-1                            as binary_double) as iter, 
                                   cast (power (2, log_vector_size - rownum) as binary_double) as width, 
                                   cast (power (2, rownum-1)                 as binary_double) as w_expon
                              from dual, (select log_vector_size from constants)
                            connect by level <= (select log_vector_size from constants) 
                           )
      dimension by (iter)
      measures (width, w_expon)
    -- lookup table for the W (twiddle factors a.k.a. roots of unity) exponents
    reference W on (select cast (rownum-1                                   as binary_double) as r,
                           cast (cos ( -2 * PI * (rownum-1) / vector_size ) as binary_double) as real,
                           cast (sin ( -2 * PI * (rownum-1) / vector_size ) as binary_double) as imag
                      from dual, (select PI, vector_size from constants)
                     connect by level <= (select vector_size from constants) 
                   )
      dimension by (r)
      measures (real, imag)
    main m
      dimension by (f)
      -- real(f) and imag(f) are the input and outputs
      -- aux_real(f) and aux_imag(f) are the O(N) auxiliary storage
      -- exp(f) is the exponent for the W factors
      -- butterfly_side(f) is 'up' if the current frequency has to be feeded with the up-pointing
      -- (sum-only) half of the butterfly, and 'down' if it must use the down-pointing (difference) side
      measures (real, imag, 0D aux_real, 0D aux_imag, 0D exp, 'xxxx' butterfly_side)
      rules sequential order 
      iterate (999999) until ( iteration_number+1 = constants.log_vector_size[0] ) (
        -- calc butterfly side (up or down)
        butterfly_side[any] = case when mod (trunc (cv(f) / butterfly.width[iteration_number]), 2D) = 0D
                                   then 'up'
                                   else 'down'
                              end,
        -- crosses (or wings) of the butterflies: complex sum or difference (to auxiliary storage) 
        aux_real[any] = case when butterfly_side[cv(f)] = 'up'
                             then + real[cv(f)] + real[cv(f) + butterfly.width[iteration_number]] 
                             else - real[cv(f)] + real[cv(f) - butterfly.width[iteration_number]] 
                        end,
        aux_imag[any] = case when butterfly_side[cv(f)] = 'up'
                             then + imag[cv(f)] + imag[cv(f) + butterfly.width[iteration_number]] 
                             else - imag[cv(f)] + imag[cv(f) - butterfly.width[iteration_number]] 
                        end,
        -- exponent of twiddle (or roots of unity) factors W
        exp[any] = case when butterfly_side[cv(f)] = 'up'
                        then 0D
                        else mod (cv(f), butterfly.width[iteration_number]) 
                             * butterfly.w_expon[iteration_number]
                   end,
        -- multiplication by the twiddle (or roots of unity) factors W (from auxiliary storage) 
        real[any] = case when butterfly_side[cv(f)] = 'up' 
                         then aux_real[cv(f)]
                         else aux_real[cv(f)] * W.real[ exp[cv(f)] ]
                            - aux_imag[cv(f)] * W.imag[ exp[cv(f)] ]
                    end,
        imag[any] = case when butterfly_side[cv(f)] = 'up'
                         then aux_imag[cv(f)]
                         else aux_real[cv(f)] * W.imag[ exp[cv(f)] ]
                            + aux_imag[cv(f)] * W.real[ exp[cv(f)] ]
                    end
      )
), dft_p_s_1_polar as (
  -- transform DFT [ P(s,1) ] in polar form
  select f, 
         sqrt ( real * real + imag * imag ) as modulus,
         case when abs(imag) < 1e-6D and abs(real) < 1e-6D then 0D else atan2 ( imag , real ) end as phase
    from dft_p_s_1
), dft_p_s_N_polar as (
  -- calc the polar form of DFT [ P(s,N) ]
  select f,
         power (modulus , cast (:N as binary_double)) as modulus,
         phase * cast (:N as binary_double) as phase
    from dft_p_s_1_polar
), dft_p_s_N as ( 
  -- transform the polar form of DFT [ P(s,N) ] in cartesian form 
  select f, 
         modulus * cos (phase) as real,
         modulus * sin (phase) as imag
    from dft_p_s_N_polar
), p_s_N as (
  -- calculate P(s,N) by using the inverse of Cooley-Tukey decimation-in-TIME
  -- NB: outputs are needed in bit-reversal order, which is exactly the order
  -- that the decimation-in-frequency outputs them, hence we save two very expensive bit-reversals
  -- See the comments above for the meaning of all steps, since 
  -- a) decimation-in-time is the same as decimation-in-frequency, with different
  --    parameters for the butterflies and different orders for the operations
  --    (the pictures in the quoted URL to the CMLAB are worth ten thousand words)
  -- b) the W sign is the opposite since we are calculating the inverse
  select f as s,
         -- definition of the inverse need 1/vector_size as a normalization term
         round(real / (select vector_size from constants),6) as probability -- note: round() returns NUMBER not BINARY_DOUBLE
         -- imaginary part is of course zero
    from (
  select f, real, imag 
    from (select f, real, imag from dft_p_s_N)
  model
    reference constants on (select 0D dummy, c.* from constants c)
      dimension by (dummy)
      measures (log_vector_size)
    reference butterfly on (select cast (rownum-1                            as binary_double) as iter, 
                                   cast (power (2, rownum-1)                 as binary_double) as width,
                                   cast (power (2, log_vector_size - rownum) as binary_double) as w_expon
                              from dual, (select log_vector_size from constants)
                            connect by level <= (select log_vector_size from constants) 
                           )
      dimension by (iter)
      measures (width, w_expon)
    reference W on (select cast (rownum-1                                   as binary_double) as r,
                           cast (cos ( +2 * PI * (rownum-1) / vector_size ) as binary_double) as real,
                           cast (sin ( +2 * PI * (rownum-1) / vector_size ) as binary_double) as imag
                      from dual, (select PI, vector_size from constants)
                     connect by level <= (select vector_size from constants) 
                   )
      dimension by (r)
      measures (real, imag)
    main m
      dimension by (f)
      measures (real, imag, 0D aux_real, 0D aux_imag, 0D exp, 'xxxx' butterfly_side)
      rules sequential order 
      iterate (999999) until ( iteration_number+1 = constants.log_vector_size[0] ) (
        -- calc butterfly side (up or down)
        butterfly_side[any] = case when mod (trunc (cv(f) / butterfly.width[iteration_number]), 2D) = 0D
                                   then 'up'
                                   else 'down'
                              end,
        -- exponent of twiddle (or roots of unity) factors W
        exp[any] = case when butterfly_side[cv(f)] = 'up'
                        then 0D
                        else mod (cv(f), butterfly.width[iteration_number]) 
                             * butterfly.w_expon[iteration_number]
                   end,
        -- multiplication by the twiddle (or roots of unity) factors W (to auxiliary storage) 
        aux_real[any] = case when butterfly_side[cv(f)] = 'up' 
                             then real[cv(f)]
                             else real[cv(f)] * W.real[ exp[cv(f)] ]
                                - imag[cv(f)] * W.imag[ exp[cv(f)] ]
                        end,
        aux_imag[any] = case when butterfly_side[cv(f)] = 'up'
                             then imag[cv(f)]
                             else real[cv(f)] * W.imag[ exp[cv(f)] ]
                                + imag[cv(f)] * W.real[ exp[cv(f)] ]
                        end,
        -- crosses (or wings) of the butterflies: complex sum or difference (from auxiliary storage)
        real[any] = case when butterfly_side[cv(f)] = 'up'
                         then + aux_real[cv(f)] + aux_real[cv(f) + butterfly.width[iteration_number]] 
                         else - aux_real[cv(f)] + aux_real[cv(f) - butterfly.width[iteration_number]] 
                    end,
        imag[any] = case when butterfly_side[cv(f)] = 'up'
                         then + aux_imag[cv(f)] + aux_imag[cv(f) + butterfly.width[iteration_number]] 
                         else - aux_imag[cv(f)] + aux_imag[cv(f) - butterfly.width[iteration_number]] 
                    end
      )
        )
)
select cast (s as number) as s, probability as probability from p_s_N
  )
  |';
   
  N := p_min_N;
  while N <= p_max_N loop
    -- exec FFT
    l_time_start := dbms_utility.get_time;
    execute immediate l_stmt using N, N, N, N, N;
    l_time_end := dbms_utility.get_time;
    
    -- insert into performance data
    insert into fft_perf (N, millis) values (N, (l_time_end - l_time_start) * 10);
    commit;
    
    -- go to next N
    if p_step_N_lin != 0 then
      N := N + p_step_N_lin;
    else 
      N := N * p_step_N_geom;
    end if;
  end loop;
end fft_test_p;
/
show errors;



