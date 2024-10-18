set terminal gif 
set xlabel 'f_num_rows / num_rows %' 
set ylabel 'f_num_distinct / num_distinct %' 
set key bottom reverse
set title 'SWRU formula for num_distinct = 100'
plot 'data.dat' using 1:2 title "num_rows / num_distinct =  1  [num_rows=  100]" with linespoint, \
     'data.dat' using 1:3 title "num_rows / num_distinct =  2  [num_rows=  200]" with linespoint, \
     'data.dat' using 1:4 title "num_rows / num_distinct =  5  [num_rows=  500]" with linespoint, \
     'data.dat' using 1:5 title "num_rows / num_distinct = 30  [num_rows= 3000]" with linespoint
