set terminal jpeg
set xlabel 'low_x'
set ylabel 'cardinality'

set key 15,2400000

set title "selection over infinitesimal ranges"
plot 'range_sel_speculation_open_open_data.dat' using 1:2 title "where x >  low_x and x <  low_x + 0.001" with linespoint, \
   'range_sel_speculation_closed_open_data.dat' using 1:2 title "where x >= low_x and x <  low_x + 0.001" with linespoint, \
   'range_sel_speculation_closed_closed_data.dat' using 1:2 title "where x >= low_x and x <= low_x + 0.001" with linespoint, \
'range_sel_speculation_open_closed_data.dat' using 1:2 title "where x >  low_x and x <= low_x + 0.001" with linespoint



