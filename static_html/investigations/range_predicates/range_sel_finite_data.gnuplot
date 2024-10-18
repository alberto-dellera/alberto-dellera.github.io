set terminal jpeg
set xlabel 'high_x'
set ylabel 'cardinality'

set key 6,3750000

set title "selection over finite open range"
plot 'range_sel_finite_02_data.dat' using 2:3 title "num_distinct = 2" with linespoint, \
     'range_sel_finite_03_data.dat' using 2:3 title "num_distinct = 3" with linespoint, \
     'range_sel_finite_04_data.dat' using 2:3 title "num_distinct = 4" with linespoint

