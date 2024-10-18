/*
  About the problem 
  "expected number of distinct values "dv" when selecting "s" balls,
   without replacement, from a bag containing "nr" balls 
   labeled with "nd" distinct values (or distinct colors, etc)"
  
  The set of balls with the same label value is also called a "bucket",
  and the "number of balls in the i-th bucket" (ie, the "number of balls
  with the same i-th value (color)") is denoted by nb[i].
  
  Example:
             bag
        =============
        | 0 0 0 0 0 |  nb[0] = 5 
        | 1 1       |  nb[1] = 2
        | 2 2 2     |  nb[2] = 3
        | 3 3       |  nb[3] = 2
        =============
        
  nd = 4
  nr = 12
  
  Example of sample runs with s=5
  { 0 0 1 2 3 }  dv = 4
  { 1 1 2 2 3 }  dv = 3
  { 0 0 0 0 0 }  dv = 1
  ...
  E [dv] = 3.1780303030303028
  
  --------------------------------------------------------------------------
  
  When nb[i] = costant = nb, the balls distribution is said to be "perfectly uniform";
  otherwise is said to be "skewed". 
  
  A (simply or weakly) "uniform" distribution is the one obtained by adding zero or one
  row to each bucket of a perfectly-uniform-distribution bag. This is obviously a
  special case of a "skewed" distribution, but it's important since it's the one
  normally assumed when we don't know the actual distribution, and we know only nr and nd. 
   
  --------------------------------------------------------------------------
   
  This class implements brute-force calculators, and formulae, for both
  the skewed and uniform case. The formulae always predict perfectly
  the brute-force results.   
  
  Author: Alberto Dell'Era, December 2005-August 2007
  alberto.dellera@gmail.com
  see www.adellera.it/investigations/distinct_balls
  $Id: DistinctBalls.java,v 1.1 2007-08-30 16:05:21 adellera Exp $
*/


import java.math.BigInteger;

public class DistinctBalls {
    
// ---------------------------- formulae -----------------------------
// This section implements the mathematical formulae 
// --------------------------------------------------------------------

// The Pnib: Probability that the bucket is not selected,
// ie that no ball contained in the bucket is selected.
// nb = number of balls in this bucket
//  s = number of balls selected from the bag
// nr = total number of balls contained in the bag
private static double Pnib (int nb, int s, int nr) { 
  
  double pnib = 1;

  for (int i = 0; i <= nb-1; ++i) {
    //pnib *= ((double)( nr-s-i  )) / (double)( nr-i );
    pnib *= ( 1.0d - s / (double)( nr-i ) );
  }    
    
  return pnib;
}  

// The general case of a "skewed" distribution
// nb = vector of balls distribution (see class header comment)
//  s = number of balls selected from the bag
public static double avg_num_distinct (int [] nb, int s) {
    
  // calc total number of balls and number of distinct values
  int nr = 0;
  int nd = 0;
  for (int i = 0; i < nb.length; ++i) {
     nr += nb[i];   
     if (nb[i] > 0) {
       ++nd;
     }
  }   
  
  assert_physical_correctness (nd, s, nr);
  
  double card = 0;
  
  for (int i = 0; i < nb.length; ++i) {
     if (nb[i] > 0) {
       card += (1 - Pnib (nb[i], s, nr));
     }   
  }
  
  return card;
}

// The special (but important) case of a (weakly) "uniform" distribution
// nd = number of distinct values in the bag
//  s = number of balls selected from the bag
// nr = total number of balls contained in the bag 
public static double avg_num_distinct_uniform (int nd, int s, int nr) {

  assert_physical_correctness (nd, s, nr);
   
  // build a (weakly) uniform distribution of balls
  // (nr % nd) buckets will have exactly one ball more
  // bb = "Big   Buckets" (=that contains one ball more)
  // sb = "Small Buckets"
  int[] nb = new int [nd];
  int balls_excess = nr % nd;
  int nb_sb = (nr-balls_excess) / nd;
  int nb_bb = nb_sb + 1;
  for (int i = 0; i < nd; ++i) {
     nb[i] = (i < balls_excess ? nb_bb : nb_sb);
  }
     
  // use the general formula
  return avg_num_distinct (nb, s);  
} // avg_num_distinct_uniform

// Same as "avg_num_distinct_uniform", but much faster due
// to some algebraic manipulations.
// See "avg_num_distinct_uniform" for parameters comments.
public static double avg_num_distinct_uniform_fast (int nd, int s, int nr) {
  // bb = "Big   Buckets" 
  // sb = "Small Buckets"
  assert_physical_correctness (nd, s, nr);
  
  int balls_excess = nr % nd;
  int nb_sb        = (nr-balls_excess) / nd;
  int nb_bb        = nb_sb + 1;
  
  int nd_bb        = balls_excess;
  int nd_sb        = nd - nd_bb;
  
  double card_bb = 0;      
  if (nd_bb > 0) {
      card_bb =  nd_bb * (1 - Pnib (nb_bb, s, nr));
  }
  
  double card_sb =  nd_sb * (1 - Pnib (nb_sb, s, nr));
     
  return card_bb + card_sb;    
} // avg_num_distinct_uniform_fast

// ---------------------------- brute-force calculators -----------------------------
// This section contains the code for brute-force calculate E[dv]
// by selecting from the bag in every possible way
// ----------------------------------------------------------------------------------

private static void assert_physical_correctness (int nd, int s, int nr) {
  if (nd < 1 || s < 0 || nr < 1 || nd > nr || s > nr) {
    throw new RuntimeException ("impossible parameters: nd="+nd+" s="+s+" nr="+nr);  
  }
}
    
// the "distinct set"
private static class DistSet {
  // "set with counter"
  // contains the sampled set of distinct values, 
  // with the number of times each value has been sampled
  // eg if we sampled the sequence (1,1,3), from a bag
  // with 4 distinct values, we have
  // dist_set[0] = 0
  // dist_set[1] = 2
  // dist_set[2] = 0
  // dist_set[3] = 1
  private int[] dist_set;

  // number of distinct values contained in the sampled sets
  // eg for the above example, num_dist=2
  // automatically maintained by add_value() and remove_value()
  public int num_dist = 0;
  
  DistSet (int nd) {
    // create dist_set[] (automatically inited to zero)
    dist_set = new int [nd];
  }

  // add a new value to the distinct set
  public void add_value (int v) {
    ++dist_set[v];
    // maintain num_dist
    if (dist_set[v] == 1) {
      ++num_dist;   
    }
  }

  // remove a value from the distinct set
  public void remove_value (int v) {
    --dist_set[v];
    // maintain num_dist
    if (dist_set[v] == 0) {
      --num_dist;   
    }
  }
}     

// the binomial coefficient 
// http://en.wikipedia.org/wiki/Binomial_coefficient
private static long cc (int n, int k) {
  BigInteger l_num = BigInteger.ONE;
  BigInteger l_den = BigInteger.ONE;

  if (k < 0 || k > n) {
    // by definition - see http://en.wikipedia.org/wiki/Binomial_coefficient  
    return 0;
  }
  for (int i = n-k+1; i <= n; ++i) {
    l_num = l_num.multiply (new BigInteger (Integer.toString (i)));
  }
  for (int i = 2; i <= k; ++i) {
    l_den = l_den.multiply (new BigInteger (Integer.toString (i)));
  }
  
  return (l_num.divide (l_den)).longValue();
}
 
// Simulates selecting "s" balls from the bag in every possible way,
// for the general "skewed" case.
// For each way (=combination), calculates the # of distinct values.
// Returns the average # of distinct values found.
public static double avg_num_distinct_brute (int[] nb, int s) { 
  // calc total number of balls and number of distinct values
  int nr = 0;
  int nd = 0;
  for (int i = 0; i < nb.length; ++i) {
     nr += nb[i];   
     if (nb[i] > 0) {
       ++nd;
     }
  }
    
  //System.out.println ("nd="+nd+" s="+s+" nr="+nr);
  assert_physical_correctness (nd, s, nr);
    
  // the in-memory bag we select balls from
  // the index is the "ball id", the value is the label-value of the ball
  int[] bag = new int[nr];
  
  // prepare the in-memory bag: build an in-memory bag with the required ball
  // distribution.
  int k = 0;
  for (int i = 0; i < nb.length; ++i) {
     for (int j = 0; j < nb[i]; ++j) {
         bag[k++] = i;
     }
  }
  
  // instantiate the "distinct set" (see comments on DistSet class)
  DistSet distSet = new DistSet (nd);
  
  // Algorithm: simulates a series of "nested loops" 
  // Eg for s=3, the combinations can be explored by
  // for (int loop0 = 0; ..., ++loop0) {
  //   for (int loop1 = loop0+1; ..., ++loop1) {
  //     for (int loop2 = loop1+1; ..., ++loop2) {
  //        // explore current combination "bag[loop0],bag[loop1],bag[loop2]"
  //     }
  //   }
  // }     
  // The algorithm below simply "simulates" this nested-loops approach
  // using an array of "s" elements, loop[], instead of "s" loop indices (loop0,loop1,etc).
  //
  // Based on
  //   http://www.merriampark.com/comb.htm
  //   (but all the comments are mine - they're my understanding of the algorithm workings)
  // which in turn quotes 
  //   "Kenneth H. Rosen, Discrete Mathematics and Its Applications, 2nd edition (NY: McGraw-Hill, 1991), pp. 284-286."

  // the s "loop indices"
  int[] loop = new int [s];
 
  // intialize the "loop indices" to the first combination
  for (int i = 0; i < s; i++) {
    loop[i] = i;
    // see below
    distSet.add_value ( bag [ loop[i] ] );
  }
  
  // accumulator of the # of distinct values sampled so far
  long num_dist_acc     = 0;

  // number of combination explored so far
  long num_combinations = 0;
  
  for(;;) {
    
    // explore current combination
    num_dist_acc += distSet.num_dist;
    ++num_combinations;
  
    // debug print
    if (1==0) {
      for (int h = 0; h < s; ++h) {
        System.out.print ("," + bag [loop[h] ] );
      }
      System.out.println(" num_dist="+distSet.num_dist);
    }
  
    // search first not-terminated "loop index" 
    int i = s - 1;
    while (i >= 0 && loop[i] == nr - s + i) {
       i--;
    }
  
    // if the outermost loop is terminated, we're done 
    if (i < 0) {
       // sanity check: check that the explored combinations cardinality
       // is the same calculated by the binomial coefficient
       if (num_combinations != cc (nr,s)) {
         throw new RuntimeException ("nd="+nd+" s="+s+" nr="+nr+" # combinations="+num_combinations+", binomial coeff="+cc (nr,s));
       }

       // return the average number of distinct values found
       return ((double)num_dist_acc) / ((double)num_combinations); 
    }
  
    // increase first not-terminated "loop index",
    // removing the old bag value from distSet,
    // and adding the new one
    distSet.remove_value ( bag [ loop[i] ] );
    loop[i] = loop[i] + 1;
    distSet.add_value ( bag [ loop[i] ] ); 
 
    // set nested "loop indices" to initial value,
    // removing the old bag value from distSet,
    // and adding the new one
    for (int j = i + 1; j < s; j++) {
      distSet.remove_value ( bag[ loop[j] ] );
      loop[j] = loop[i] + j - i;
      distSet.add_value ( bag[ loop[j] ] );
    }
  
  } // for(;;) 
 
} // avg_num_distinct_brute  
    
// Special case of a (weakly) "uniform" distribution.    
public static double avg_num_distinct_uniform_brute (int nd, int s, int nr) {
  // build a uniform (non-skewed) distribution of balls
  // (nr % nd) buckets will have exactly one ball more
  // bb = "Big   Buckets" 
  // sb = "Small Buckets"
  int[] nb = new int [nd];
  int balls_excess = nr % nd;
  int nb_sb = (nr-balls_excess) / nd;
  int nb_bb = nb_sb + 1;
  for (int i = 0; i < nd; ++i) {
     nb[i] = (i < balls_excess ? nb_bb : nb_sb);
  }
  
  // call the general brute-force simulator
  return avg_num_distinct_brute (nb, s);
}    
 
// ---------------------------- test harnesses --------------------------------------
// This section contains the code that builds a family of bags and checks that
// the formulae and the brute-force calculators return the same value.
// ----------------------------------------------------------------------------------

// compares the brute-force and formula outputs for a (weakly) "uniform" distribution
private static int compare_uniform (int nd, int s, int nr) {
  double res       = avg_num_distinct_uniform       (nd, s, nr);
  double res_brute = avg_num_distinct_uniform_brute (nd, s, nr);
  if (Math.abs (res - res_brute) > 1e-10) 
  {
    System.out.println ("different at nd="+nd+" s="+s+" nr="+nr);
    System.out.println ("  formula = "+res);
    System.out.println ("  brute   = "+res_brute);  
    return 1;            
  }   
  return 0;
}    

// Checks exhaustively a family of "uniform" distributions,
// comparing the brute-force and formula outputs.
// The "family" is defined by all permutations of distributions parameters
// that are <= than the input parameters:
// 1 <= nd <= nd_max
// 1 <= nr <= nd_max
// 0 <= s  <= s_max
private static void exhaustive_check_uniform (int nd_max, int s_max, int nr_max) {
   int this_ko;
   int num_ko = 0;
   int num_checked = 0;
   for (int nd = 1; nd <= nd_max; ++nd) {
      for (int nr = nd; nr <= nr_max; ++nr) {
          for (int s = 0; s <= nr && s <= s_max; ++s) {
              System.out.print (num_checked+"| nd="+nd+" s="+s+" nr="+nr);
              num_ko += this_ko = compare_uniform (nd, s, nr);
              System.out.println ( (this_ko == 0 ? " ok" : " KO") 
                  + " avg="+avg_num_distinct_uniform (nd, s, nr) );
              ++num_checked;
          }
      }
   }
   System.out.println ("exhaustively checked "+num_checked+" permutations"+
                       " for nd<="+nd_max+" s<="+s_max+" nr<="+nr_max+"; num_ko="+num_ko);
}

// Checks randomly a family of "uniform" distributions,
// comparing the brute-force and formula outputs.
// The "family" is defined by all permutations of distributions parameters
// that are <= than the input parameters:
// 1 <= nd <= nd_max
// 1 <= nr <= nd_max
// 0 <= s  <= s_max
private static void monteCarlo_check_uniform (int nd_max, int s_max, int nr_max) {
   int this_ko;
   int num_ko = 0;
   int num_checked = 0;
   
   java.util.Random r = new java.util.Random(); 
   for (;;) {
      int nd = 1  + r.nextInt (nd_max);
      int nr = nd + r.nextInt (nr_max - nd + 1);
      int s  =      r.nextInt (Math.min (nr, s_max) + 1);
      System.out.print (num_checked+"| nd="+nd+" s="+s+" nr="+nr);
      num_ko += this_ko = compare_uniform (nd, s, nr);
      System.out.println (this_ko == 0 ? " ok" : " KO");
      ++num_checked;
      if (num_checked % 100 == 0) {
         System.out.println ("checked "+num_checked+" random permutations"+
                       " for nd<="+nd_max+" s<="+s_max+" nr<="+nr_max+"; num_ko="+num_ko);  
      }    
   }
}

// transform parameters and forwards 
private static void main_uniform (String[] args) {
  String method = args[0].toLowerCase();
  int nd = Integer.valueOf (args[1]).intValue();
  int  s = Integer.valueOf (args[2]).intValue();
  int nr = Integer.valueOf (args[3]).intValue();
  
  if ("exhaustive".equals (method)) {
    exhaustive_check_uniform (nd, s, nr);
  } else if ("montecarlo".equals (method)) {
    monteCarlo_check_uniform (nd, s, nr);   
  } else {
    System.out.println ("illegal method="+method);
    usage();
  } 
}

// compares the brute-force and formula outputs for a general "skewed" distribution
private static int compare_skewed (int[] nb, int s) {
    
  double res       = avg_num_distinct       (nb, s);
  double res_brute = avg_num_distinct_brute (nb, s);
  
  if (Math.abs (res - res_brute) > 1e-10) 
  {
    System.out.println ("different at s="+s);
    System.out.println ("  formula = "+res);
    System.out.println ("  brute   = "+res_brute);  
    return 1;            
  }   
  return 0;
}    

// Checks exhaustively a family of "uniform" distributions,
// comparing the brute-force and formula outputs.
// The "family" is defined by 
// 0 <= s  <= s_max
private static void exhaustive_check_skewed (int[] nb, int s_max, boolean printLatexTable) {
  int this_ko;
  int num_ko = 0;
  int num_checked = 0;
  
  int nr = 0;
  for (int i = 0; i < nb.length; ++i) {
      nr += nb[i];
  }
   
  if (printLatexTable) {
    System.out.println ("\\begin{array}[t]{|r||l|l||l|}");
    System.out.println ("\\hline");
    System.out.println ("s & E[D_v] (formula) & avg[D_v] (brute force) & abs(diff) \\\\ ");
    System.out.println ("\\hline");    
  }
  
  for (int s = 0; s <= nr && s <= s_max; ++s) {
      if (!printLatexTable) {
        System.out.print (num_checked+"| s="+s);
      }
      num_ko += this_ko = compare_skewed (nb, s);
      if (!printLatexTable) {
        System.out.println ((this_ko == 0 ? " ok" : " KO") + " avg="+avg_num_distinct (nb, s));
      };
      if (printLatexTable) {
         double res       = avg_num_distinct       (nb, s);
         double res_brute = avg_num_distinct_brute (nb, s);
         System.out.println (s + " & " + res + " & " + res_brute + " & " + Math.abs (res - res_brute) + " \\\\");  
      }
      ++num_checked;
  }
  if (printLatexTable) {
    System.out.println ("\\hline");
    System.out.println ("\\end{array}");
  }
  
  System.out.println ("exhaustively checked "+num_checked+" permutations"+
                      " for s<="+s_max+"; num_ko="+num_ko);
}

// transform parameters and forwards 
private static void main_skewed (String[] args) {
   String method = args[0].toLowerCase();
   
   // convert nb[] values
   int nd = args.length-2;
   int[] nb = new int[nd];
   for (int i = 0; i < nd; ++i) {
     nb[i] = Integer.valueOf (args[i+1]).intValue();
   }
   int s = Integer.valueOf (args[args.length-1]).intValue();
   
   if ("exhaustive".equals (method) || "exhaustive_latex".equals (method)) {
    exhaustive_check_skewed (nb, s, "exhaustive_latex".equals (method));
  } else if ("montecarlo".equals (method.toLowerCase())) {
    //monteCarlo_check_skewed (nd, s, nr);   
  } else {
    System.out.println ("illegal method="+method);
    usage();
  }    
}

private static void usage() {
  System.out.println ("usage: java DistinctBalls {uniform|skewed} {exhaustive|montecarlo} <args>");
  System.out.println ("       for uniform, <args> = nd s nr");
  System.out.println ("       for skewed,  <args> = nb[0] nb[1] .. nb[nd-1] s");
  System.out.println ("Examples:");
  System.out.println ("java DistinctBalls uniform exhaustive 3 2 10");
  System.out.println ("java DistinctBalls skewed  exhaustive 1 10 3 11 1 2 1 10");
  System.exit(0);   
}

public static void main (String[] args) {
    
  if (args.length < 4) usage();
  
  String distributionType = args[0].toLowerCase();
  
  // extract last arguments
  String[] argsLast = new String[args.length-1];
  for (int i = 0; i < argsLast.length; ++i) {
      argsLast[i] = args [i+1];
  }
  
  if ("uniform".equals (distributionType)) {
      main_uniform (argsLast);
  } else if ("skewed".equals (distributionType)) {
      main_skewed (argsLast);  
  } else {
    System.out.println ("illegal distribution type="+distributionType);
    usage();
  } 
}

}

