#!/bin/sh
sqlplus dellera/dellera@oracle10g @swru_graph_data.sql  
gnuplot swru_graph_data.gnuplot > swru_graph_data.gif  
