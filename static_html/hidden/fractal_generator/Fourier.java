import java.lang.Math.*;

class Fourier {

public interface SpectrumProvider {
	double modulus (double frequence, double phase);
}

	//---------------------------------------------------------------------
	// Routine fourn() di Press (1992, p. 523), da consultare per commenti
	// piu' approfonditi.
	// Calcola la (anti)trasformata veloce di Fourier (FFT), con input e
	// output complessi (i posti pari sono la parte reale dei dati mentre
	// quelli dispari la parte immaginaria); l'ordine delle armoniche e'
	// standard wrap-around.
	// data  : dati da trasformare 
	// nn    : dimensioni dei lati dell'array (passare nn[1]=nn[2]=N per
	//         le immagini).
	//         (N.B.Tutti gli elementi devono essere potenza di due, e
	//         questo non viene controllato dalla routine).
	// ndim  : n. dimensioni (passare 2 per immagini)
	// isign : segno dell'esponenziale (-1 per diretta)
	//---------------------------------------------------------------------
	// esempio : double nn[2]; nn[0] = 16; nn[1] = 16;
	// fourn (data, nn, 2, -1); // tr. diretta
private static void fourn (double [] data, int [] nn, int ndim, int isign)
  {
	 int idim;
	 int ntot = 1;
	
	 for (idim=1; idim <= ndim; idim++)
	   ntot *= nn [idim-1];
	
	 int nprev = 1;
	 for (idim = ndim; idim >= 1; idim--) {// main loop sulle dimensioni
	   int n = nn [idim-1];
	   int nrem = ntot / (n*nprev);
	   int ip1 = nprev << 1;
	   int ip2 = ip1*n;
	   int ip3 = ip2*nrem;
	
	   // bit-reversal
	   int i2rev=1;
	   for (int i2 = 1;  i2 <= ip2; i2 += ip1) {
	      if (i2 < i2rev) {
	        for (int i1 = i2; i1 <= i2+ip1-2; i1+=2) {
		  for (int i3 = i1; i3 <= ip3; i3 += ip2) {
	            double swaptemp;
	            int i3rev = i2rev+i3-i2;
	            //SWAP (data [i3  ], data [i3rev  ]);
                    swaptemp = data [i3  -1]; data [i3  -1] = data [i3rev  -1]; data [i3rev  -1] = swaptemp;  
		    //SWAP (data [i3+1], data [i3rev+1]);
                    swaptemp = data [i3+1-1]; data [i3+1-1] = data [i3rev+1-1]; data [i3rev+1-1] = swaptemp;
		  }
	        }
	      }
	      int ibit = ip2 >>> 1;
	      while (ibit >= ip1 && i2rev > ibit) {
		i2rev -= ibit;
	        ibit >>>= 1;
	      }
	      i2rev += ibit;
	   }// for (int i2=
	
	   // Danielson-Lanczos
	   int ifp1 = ip1;
	   while (ifp1 < ip2) {
	     int ifp2 = ifp1 << 1;
	     // inizializzazioni ricorrenza trigonometrica
	     double theta = isign * 2.0 * Math.PI / (ifp2/ip1);
	     double wtemp = Math.sin (0.5 * theta);
	     double wpr   = -2.0 * wtemp*wtemp;
	     double wpi   = Math.sin (theta);
	     double wr    = 1.0;
	     double wi    = 0.0;
	     for (int i3 = 1; i3 <= ifp1; i3 += ip1) {
	       for (int i1 = i3; i1 <= i3+ip1-2; i1+= 2) {
		 for (int i2 = i1; i2 <= ip3; i2 += ifp2) {
	           int k1 = i2;
		   int k2 = k1 + ifp1;
		   double tempr = wr * data [k2  -1] - wi * data [k2+1-1];
		   double tempi = wr * data [k2+1-1] + wi * data [k2  -1];
		   data [k2  -1] = data [k1  -1] - tempr;
		   data [k2+1-1] = data [k1+1-1] - tempi;
		   data [k1  -1] += tempr;
		   data [k1+1-1] += tempi;
		 }
	       }
	       wr = (wtemp = wr) * wpr - wi    * wpi + wr;
	       wi =           wi * wpr + wtemp * wpi + wi;
	     }
	     ifp1 = ifp2;
	   }// while (ifp1 <
	   nprev *= n;
	 }
  }

//--------------------------------------------------------------------
// Generazione di spettri del tipo rho^(-beta) * H (teta), ove beta e la
// funzione H(teta) sono fornite dall'utente (in coda alla funzione sono
// fornite alcune funzioni interessanti).
// H (teta) deve essere periodica di periodo M_PI, per rispettare la
// propriet… di simmetria polare degli spettri stocastici.
// Tutti i parametri sono analoghi alla funzione sintesi_spettrale(),
// tranne ovviamente beta e acca. Anche il codice Š in gran parte
// identico a sintesi_spettrale(). Volendo, Š possibile ottenere gli
// stessi risultati di sintesi_spettrale passando una funzione acca()
// che restituisca sempre 1.0, eccetto il fatto che sintesi_spettrale()
// va meno facilmente in underflow (eventualit… comunque remotissima).
// beta : coefficinte beta dello spettro
// acca : user-defined funzione H (teta)
// lato, imm, var, seme, chi_squared, oversampling : cfr. sintesi_spettrale()
// variabili globali : no
//--------------------------------------------------------------------
// Esempio (provate!) :
// ventaglio_doppio_init (M_PI/8, M_PI/40, M_PI/8+M_PI/2, M_PI/40);
// fratt_gen (1.0, ventaglio_doppio, 512, tessuto, 1, 34, 1, 1);
public static void fratt_gen (SpectrumProvider spectrum, 
                Matrix imm,
                double var, int oversampling)
// generazione deterministica (debug)
{

 int i, j;
 int lato = imm.getSquareDim();

 // controllo che lato sia potenza di due
 if (lato <= 0 ||!isPow2(lato)) {
   System.out.println ("lato non e' potenza di due.Abort.");
   return;
 }
 // controllo che oversampling sia potenza di due
  if (oversampling <= 0 ||!isPow2(oversampling)) {
   System.out.println ("oversampling non e' potenza di due.Abort.");
   return;
 }

 // gestione generatori numeri casuali
 if (var > 0)
   Random.initgauss ((double)var);

 // lato dell'immagine di cui utilizzeremo solo la porzione centrale
 int l = lato * oversampling;

 // spettro (2*N*N numeri reali rappresentanti N*N numeri complessi;
 // se p e' pari    sp[p] e' la parte reale       del p/2 esimo n. complesso,
 // se p e' dispari sp[p] e' la parte immaginaria del (p-1)/2 esimo numero).

 double [] sp = new double [2*l*l]; 

 ////////////////// generazione armoniche libere //////////////////////
 // Essendo la antitrasformata reale le armoniche devono rispettare
 // la legge di simmetria coniugata sp (u, v) = sp* (u, v). Inoltre,
 // data la periodicita' dello spettro, ovvero dato che
 // sp (u + kl, v + ml) = sp (u,v), per k,m interi >=< 0,
 // esistono sottili relazioni lungo i bordi dello spettro di cui
 // occorre tenere conto. Facendo i calcoli, tali vincoli restringono
 // i gradi di liberta' dello spettro da (2l)*(2l) ad l*l, come e'
 // intuitivo avendo una figura di l*l numeri reali. Dovrei quindi avere
 // esaurito tutte le simmetrie possibili.
 /////////////////////////////////////////////////////////////////////

 int u0 = l/2-1; // (u0, v0) == centro spettro (frequenza zero)
 int v0 = l/2-1;
 final double k = 1.0;
 int u, v; // frequenze complesse
 for (v = 0; v <= l/2; v++) {
   for (u = -l/2+1; u <= l/2; u++) {
     if ( (v == 0 && u < 0) || (v == l/2 && u < 0))
       continue;
     // armonica singolare ? Sulle armoniche singolari lo spettro
     // deve essere reale e distribuito come chi-squared-1 con doppia
     // varianza
     boolean arm_sing = 
                    (v == 0   && u == 0  ) ||
                    (v == 0   && u == l/2) ||
                    (v == l/2 && u == 0  ) ||
                    (v == l/2 && u == l/2);
     // imposizione fase distribuita uniformemente
     double fase; // fase armonica corrente
     fase = ( arm_sing ?
              0.0 : // spettro reale
              Math.PI * ( 2.0 * Math.random() - 1.0)
            );
     // imposizione quadrato del modulo gaussiano (chi-squared-1)
     // oppure chi-squared-2
     double modulo;
     double sqrf = u*u + v*v;// f (ovvero rho) al quadrato
     double f = Math.sqrt (sqrf);
     if (sqrf > 0) {
         double g1    = Random.gauss();
         double g2    = (arm_sing ? 0.0 : Random.gauss());
         double coeff = (arm_sing ? 1.0 : 0.5);
         double phase = atg (u, v);
         modulo = Math.sqrt (
          (g1*g1+g2*g2)* coeff * k *
          //Math.pow (sqrf, - beta/2.0) * acca (Math.atg (u, v))//powl (sqrf, -(2.0*H+2.0) / 2.0)
		spectrum.modulus (f, phase)
                        );
      }
     else
       modulo = l*l*k; // euristico
     if (var > 0) {
       if (modulo < 0) {
         fase += Math.PI;
         modulo = - modulo;
       }
     }
     int disp = (v+v0) * l + (u+u0); // displacement
     sp [(disp<<1)  ] = modulo * Math.cos (fase);
     sp [(disp<<1)+1] = modulo * Math.sin (fase);
   }
 }

 ////// generazione armoniche legate dalla simmetria coniugata ////////
 // Molte leggi di simmetria sono alquanto subdole, per cui attenzione
 // alle modifiche.
 //////////////////////////////////////////////////////////////////////
 int dispt; // displacement target
 int disps; // displacement source
 for (u = -l/2+1; u < 0; u++) {
   // sp(-u, 0) = sp*(u, 0)
   dispt  = (0+v0) * l + (+u+u0);
   disps  = (0+v0) * l + (-u+u0);
   sp [ dispt<<1   ] =  sp [ disps<<1   ];
   sp [(dispt<<1)+1] = -sp [(disps<<1)+1];
   // sp(-u, l/2) = sp*(u, l/2)
   dispt  = (l/2+v0) * l + (+u+u0);
   disps  = (l/2+v0) * l + (-u+u0);
   sp [ dispt<<1   ] =  sp [ disps<<1   ];
   sp [(dispt<<1)+1] = -sp [(disps<<1)+1];
 }
 // sp (-u, -v) = sp*(u, v)
 for (v = -l/2+1; v < 0; v++) {
   for (u = -l/2+1; u < l/2; u++) {
      dispt  = ( v+v0) * l + ( u+u0);
      disps  = (-v+v0) * l + (-u+u0);
      sp [ dispt<<1   ] =  sp [ disps<<1   ];
      sp [(dispt<<1)+1] = -sp [(disps<<1)+1];
   }
 }
 // sp (l/2, v) = sp*(l/2, -v);
 for (v = -l/2+1; v < 0; v++) {
   dispt  = ( v+v0) * l + (l/2+u0);
   disps  = (-v+v0) * l + (l/2+u0);
   sp [ dispt<<1   ] =  sp [ disps<<1   ];
   sp [(dispt<<1)+1] = -sp [(disps<<1)+1];
 }


 /////////////////// antitrasformata di Fourier ///////////////////////
 // chiamata FFT (il risultato rimpiazza sp)
 int [] nn = new int[] {l, l};
 fourn (sp, nn, 2, 1);

 // Copia dell'immagine in imm.
 // Compensiamo per l'origine dello spettro in v0, u0 anziche' in
 // 0, 0 (cfr. [Bow, pag 180, formula (8.41)]). Usiamo delle look-up
 // tables (espr ed espi) per l'esponenziale.
 // Non ho spostato lo spettro in l/2, l/2 (ottenendo una formula piu'
 // semplice e veloce) per omogeneita' con gli altri programmi. Il tempo
 // speso qui e' irrilevante in confronto con quello speso per la FFT.
 double [] espr = new double [l];
 double [] espi = new double [l];

 for (i = 0; i < l; i++) {
   double arg = - 2 * Math.PI * i / (double) l;
   espr [i] = Math.cos (arg);
   espi [i] = Math.sin (arg);
 }

 int x0, y0;
 y0 = x0 = l/2 - lato/2;
 int l_mask = l - 1;
 for (int y = 0; y < lato; y++)
   for (int x = 0; x < lato; x++) {
   i = x + x0;
   j = y + y0;
   double t;
   int disp = i*l+j;
   int esp_disp = ((l/2-1) * (i+j)) & l_mask;
   double [][] imm_matrix = imm.getMatrix();
   imm_matrix [y][x] =
    (t=sp [ disp<<1   ]) * espr [esp_disp]
                           - sp [(disp<<1)+1]  * espi [esp_disp];
   //sp [(disp<<1)+1] =    sp [(disp<<1)+1]  * espr [esp_disp]
   //                    + t                 * espi [esp_disp];
 }
}

private static boolean isPow2 (int k) {
	while (k > 1) {
 		if (k % 2 != 0)
   			return false;
  		else
    			k /= 2;
	}
 	return true;
}

//--------------------------------------------------------------------
// Calcola l'angolo che il vettore (x,y) forma con il semiasse positivo,
// angolo compreso fra -M_PI e +M_PI. Questa funzione NON coincide con
// l'arcontangente di y / x.
// x : ascissa  del punto
// y : ordinata del punto
// return value : vedi descrizione
// variabili globali : no
//--------------------------------------------------------------------
public static double atg (double x, double y)
{
 if (x == 0.0 && y == 0.0) {
	throw new ArithmeticException ("atg() : il punto coincide con l'origine.");
 }
 if (x > 0)
   return Math.atan (y / x);
 if (x < 0) {
   double temp = Math.atan (y / x);
   return (y >= 0 ? temp + Math.PI : temp - Math.PI);
 }
 return (y > 0 ? +Math.PI/2.0 : -Math.PI/2.0);
}
	
}

class Random {

private static int iset = 0;
private static double gset;

//////////////////////////////////////////////////////////////////////
// Generatore di rumore gaussiano (bianco) con valore atteso 0 e
// varianza unitaria. 
//////////////////////////////////////////////////////////////////////
private static double gasdev ()
{
 double fac, rsq, v1, v2;

 if (iset == 0) {
   do {
     v1 = 2.0 * Math.random() - 1.0;
     v2 = 2.0 * Math.random() - 1.0;
     rsq = v1*v1 + v2*v2;
   } while (rsq >= 1.0 || rsq == 0.0);
   fac = Math.sqrt (-2.0*Math.log(rsq)/rsq);
   gset = v1*fac;
   iset = 1;
   return v2*fac;
 } else {
   iset = 0;
   return gset;
 }
}

//////////////////////////////////////////////////////////////////////
// Interfacce verso gasdev().
//////////////////////////////////////////////////////////////////////
private static double varianza = -1;
private static double sigma = -1;
public static void initgauss (double varianza)
{
 if (varianza <= 0) {
    throw new ArithmeticException ("varianza negativa o nulla in initgauss().");
 } 
 Random.varianza = varianza;
 sigma = Math.sqrt (varianza);
}
public static double gauss ()
{
 if (varianza < 0)
   initgauss (1.0);
 return sigma*gasdev ();
}


}

