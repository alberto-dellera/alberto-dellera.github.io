/*
<APPLET code="JFbm3DApplet.class" width=500 height=400> </APPLET>
*/

import java.awt.*;
import java.awt.event.*;
import java.applet.*;

class ImageCanvas extends Canvas {
	Image image;
	ImageCanvas () { setSize (256,256); }	
	synchronized void setImage (Image image) {
		this.image = image;		
		repaint();
	}
	synchronized Image getImage () {
		return image;
	}
	public void paint (Graphics g) {
		Image imageCopy = getImage(); // copy to avoid thread-races
		if (imageCopy != null) {
			g.drawImage (imageCopy,0,0,this);
			g.drawString ("fractal brownian motion" ,10,40);
		} 
	}
}

class ImageBuilder implements Runnable {
	private double newBeta = Double.MIN_VALUE;
	private double curBeta = Double.MIN_VALUE;
	synchronized void setNewBeta (double beta) 
		{ newBeta = beta; wasUpdated = true; notify(); }
	private SpectrumGenerator newSpectGen = null;
	private SpectrumGenerator curSpectGen = null;
	synchronized void setNewSpectrumGenerator (SpectrumGenerator spectrum) 
		{ newSpectGen = spectrum; wasUpdated = true; notify();}
	private boolean newBAndW = false;
	private boolean curBAndW = false;
	synchronized void setNewBAndW (boolean bAndW) 
		{ newBAndW = bAndW; wasUpdated = true; notify(); }
	private boolean touched = false;
	private boolean wasUpdated = false;
	synchronized void touch () 
		{ touched = true; wasUpdated = true; notify();}

	private synchronized boolean betaChanged() 
		{ return newBeta != curBeta; } 
	private synchronized boolean spectrumChanged()
		 { return newSpectGen !=  curSpectGen; }
	private synchronized boolean bANdWChanged() 
		{ return newBAndW != curBAndW; }
	public void run() {
	    for (;;) {
		// wait for changes in state
		boolean betaChanged, spectrumChanged, bANdWChanged, wasTouched;
		synchronized (this) {
			while (!wasUpdated) {
				try {
					wait();
				} catch (InterruptedException e) {}
			}
			while (wasUpdated) {
				try {
					wasUpdated = false;
					wait (100);
				} catch (InterruptedException e) {}
			}
		}
			
		synchronized (this) {
			betaChanged = betaChanged();
		      	curBeta = newBeta;	
			spectrumChanged = spectrumChanged();  	
			curSpectGen = newSpectGen;
			bANdWChanged = bANdWChanged();	
			curBAndW  = newBAndW;		
			wasTouched = touched; touched = false;
		}
		curSpectGen.setBeta (curBeta);
		// calc new image
		if (betaChanged || spectrumChanged || wasTouched) {
			generateNewMatrix();
		}
		showMatrix();
		applet.showStatus ("done");
 	    }
	}

	private void showMatrix() {
		applet.showStatus ("calculating image");
		image = matrix.getAsImage(curBAndW, applet);
		applet.showStatus ("repainting image");
		imageCanvas.setImage (image);
	}
	private void generateNewMatrix() {
		applet.showStatus ("starting fourier transformations");
		Fourier.fratt_gen (curSpectGen, matrix, 1.0, 1);
	}

	Applet applet;
	Matrix matrix = new Matrix (256,256);
	ImageCanvas imageCanvas;
	Image image;

	ImageBuilder (Applet applet, ImageCanvas imageCanvas) {
		this.applet = applet;
		this.imageCanvas = imageCanvas;
	}
}

interface BetaSetter {
	public void setBeta (double beta);
}

abstract class SpectrumGenerator implements Fourier.SpectrumProvider, BetaSetter {};

public class JFbm3DApplet extends Applet {
	public static final String FBMTYPE_ISO        ="isotropic";
	public static final String FBMTYPE_ANIGAUSSIAN="anisotropic - gaussian";
	public static final String FBMTYPE_ANISLICE   ="anisotropic - slice";
	Image image;
	Scrollbar betaScrollbar;
	Checkbox colorToggle;

	private double beta = 3.0;
	private final int SCROLLBARMAX = 500;
	private final double SCROLLBARBETAMAX = 8.0;

	SpectrumGenerator spectrumGeneratorIso;
	SpectrumGenerator spectrumGeneratorAniGauss;
	SpectrumGenerator spectrumGeneratorAniSlice;

	ImageCanvas imageCanvas = new ImageCanvas();
	final ImageBuilder imageBuilder = new ImageBuilder (this, imageCanvas);

	public void init() {
		spectrumGeneratorIso      = new SpectrumGeneratorIso();
		spectrumGeneratorAniGauss = new SpectrumGeneratorAniGauss();
		spectrumGeneratorAniSlice = new SpectrumGeneratorAniSlice();

		imageBuilder.setNewSpectrumGenerator (spectrumGeneratorIso);
		imageBuilder.setNewBeta (beta);


		betaScrollbar = new Scrollbar (	Scrollbar.VERTICAL,
						(int)(SCROLLBARMAX * beta/SCROLLBARBETAMAX),
						1,0,SCROLLBARMAX);
		betaScrollbar.setSize (10,10);

		betaScrollbar.addAdjustmentListener (new AdjustmentListener() {
			public void adjustmentValueChanged (AdjustmentEvent e) {
				double beta = e.getValue() * SCROLLBARBETAMAX / 
						betaScrollbar.getMaximum();
				//System.out.println ("beta=" +beta+" e="+e );
				imageBuilder.setNewBeta (beta);
			}
		});

		Panel highPanel =  new Panel();
		highPanel.setLayout (new BorderLayout ());
		highPanel.add (imageCanvas, BorderLayout.CENTER);
		highPanel.add (betaScrollbar, BorderLayout.EAST);
		Choice fbmTypeChoice = new Choice();
		fbmTypeChoice.add (FBMTYPE_ISO);
		fbmTypeChoice.add (FBMTYPE_ANIGAUSSIAN);
		fbmTypeChoice.add (FBMTYPE_ANISLICE);
		fbmTypeChoice.addItemListener (new ItemListener() {
			public void itemStateChanged(ItemEvent e) {
				String fbmType = (String)e.getItem();
				if (fbmType == FBMTYPE_ISO) {
					imageBuilder.setNewSpectrumGenerator (spectrumGeneratorIso);
				} else if (fbmType == FBMTYPE_ANIGAUSSIAN) {
					imageBuilder.setNewSpectrumGenerator (spectrumGeneratorAniGauss);
				} else if (fbmType == FBMTYPE_ANISLICE) {
					imageBuilder.setNewSpectrumGenerator (spectrumGeneratorAniSlice);
				} 
			}
		});
		highPanel.add (fbmTypeChoice, BorderLayout.NORTH);
		colorToggle = new Checkbox ("B/W");
		colorToggle.setState (false);
		colorToggle.addItemListener (new ItemListener() {
			public void itemStateChanged(ItemEvent e) {
				imageBuilder.setNewBAndW (colorToggle.getState());
			}
		});
		Panel colorTogglePanel = new Panel();
		colorTogglePanel.setLayout (new FlowLayout (FlowLayout.LEFT));
		colorTogglePanel.add (colorToggle);
		highPanel.add (colorTogglePanel, BorderLayout.SOUTH);
		add (highPanel);

	}

	Thread thread;
	public void start () {
		if (thread == null) {
			thread = new Thread (imageBuilder);
			thread.start();
		}
		imageBuilder.touch();
	}

}

class SpectrumGeneratorIso extends SpectrumGenerator {
	private double beta;
	public double modulus (double frequence, double phase) {
		return Math.pow (frequence, -beta);
	}
	public void setBeta (double beta) { this.beta = beta; }
}

class SpectrumGeneratorAniGauss extends SpectrumGenerator {
	private double beta;
	private double sigma = 0.2;
	private double mu = 0.7;
	private final static double M_SQRT2 = 1.41421356237309504880;

	public double modulus (double frequence, double phase) {
		double temp = Math.abs (phase - mu) % Math.PI;
 		if (temp > Math.PI / 2.0)
   			temp = Math.PI - temp;
 		temp /= M_SQRT2 * sigma;
 		return Math.exp (- temp*temp) / (Math.sqrt (2*Math.PI) * sigma);
	}
	public void setBeta (double beta) { this.beta = beta; }
}

class SpectrumGeneratorAniSlice extends SpectrumGenerator {
	private double beta;
	private double center = 0.7;
	private double halfAperture = 0.2;

	public double modulus (double frequence, double phase) {
		double temp = Math.abs (phase - center) %  Math.PI;
 		if (temp > Math.PI / 2.0)
 			temp = Math.PI - temp;
 		return (temp <= halfAperture ? 1.0 : 0.0);
	}
	public void setBeta (double beta) { this.beta = beta; }
}

