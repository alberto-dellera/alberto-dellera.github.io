set terminal jpeg
set xlabel 'low_x'
set ylabel 'cardinality'

set key 6,1200000

set title "selection over infinitesimal closed range"
plot 'range_sel_closed_inf_02_data.dat' using 1:2 title "num_distinct = 2" with linespoint, \
   'range_sel_closed_inf_03_data.dat' using 1:2 title "num_distinct = 3" with linespoint, \
   'range_sel_closed_inf_04_data.dat' using 1:2 title "num_distinct = 4" with linespoint

