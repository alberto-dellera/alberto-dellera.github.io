
with die_ieee as (
  -- the die_ieee casted using IEEE 754 arithmetic
  select cast (face_value  as binary_double) as face_value,
         cast (probability as binary_double) as probability
    from die
), base_constants as (  
  -- Calculate max_s_1, the highest s for which P(s,1) is > 0,
  -- that is, the max face value of the die_ieee
  select max (face_value) as max_s_1  
    from die_ieee 
   where probability != 0D
), derived_constants as (
  -- Calculate max_s_N, the highest s for which P(s,N) is > 0, which is (:N * max_s_1):
  -- for example, max_s_1=8, after 3 throws the max s observed will be 8*3=24.
  -- Hence we need to calculate P(s,N) over the range 0 .. max_s_N,
  -- that is, we need to calculate the FT over max_s_N * :N + 1 values.
  -- We also store in vector_size the size of the vector - note that it is not
  -- required that vector_size is a power of two 
  select max_s_1,
         max_s_1 * cast (:N as binary_double)      as max_s_N,
         max_s_1 * cast (:N as binary_double) + 1D as vector_size
    from base_constants
), constants as (
  -- add the useful PI constant
  select vector_size,
         3.14159265358979323846264338327950288419716939937510D as PI
    from derived_constants
), s_sequence as (
  -- build the sequence of all possible s values: 0..vector_size
  -- this is of course the number of frequencies as well
  select cast (rownum-1 as binary_double) as s from dual connect by level <= (select vector_size from constants)
), p_s_1 as (
  -- set P(s,1) over all possible values of s (zero for non-existent face value) 
  select s, nvl (die_ieee.probability, 0D) as probability
    from s_sequence, die_ieee
   where s_sequence.s = die_ieee.face_value(+)
     and die_ieee.probability(+) != 0D
), w as (
  -- the W (orthogonal base of the Fourier Transform) lookup table (index is r)
  select cast (rownum-1                                   as binary_double) as r,
         cast (cos ( -2 * PI * (rownum-1) / vector_size ) as binary_double) as real,
         cast (sin ( -2 * PI * (rownum-1) / vector_size ) as binary_double) as imag
    from dual, (select PI, vector_size from constants)
 connect by level <= (select vector_size from constants) 
), dft_p_s_1 as (
  -- compute DFT [ P(s,1) ] using the FT definition
  select f,
         sum ( p_s_1.probability * w.real ) as real,
         sum ( p_s_1.probability * w.imag ) as imag
    from p_s_1, (select s as f from s_sequence) freqs, w
   where mod (s * f, (select vector_size from constants)) = w.r
   group by f
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
), w_inv as (
  -- the inverted W (orthogonal base of the inverted Fourier Transform) lookup table (index is r)
  select cast (rownum-1                                   as binary_double)  as r,
         cast (cos ( +2 * PI * (rownum-1) / vector_size ) as binary_double)  as real,
         cast (sin ( +2 * PI * (rownum-1) / vector_size ) as binary_double)  as imag
    from dual, (select PI, vector_size from constants)
 connect by level <= (select vector_size from constants) 
), p_s_N as (
  -- calculate P(s,N) by using the definition of the inverted Fourier Transform
  select s,
         round ( sum ( dft_p_s_N.real * w_inv.real - dft_p_s_N.imag * w_inv.imag ) 
                        / (select vector_size from constants)
                , 6)  as probability -- note: round() returns NUMBER not BINARY_DOUBLE
         --sum ( dft_p_s_N.real * w_inv.imag + dft_p_s_N.imag * w_inv.real ) as imag
    from dft_p_s_N, (select s from s_sequence), w_inv
   where mod (s * f, (select vector_size from constants)) = w_inv.r
   group by s
)
select cast (s as number) s, probability from p_s_N
order by s
;

