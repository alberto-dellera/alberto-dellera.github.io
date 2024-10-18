import java.awt.*;

class Matrix {
	private double[][] matrix;
	int nCols, nRows;

	public Matrix (int nRows, int nCols) {
		this.nCols = nCols;
		this.nRows = nRows;

		matrix = new double[nRows][nCols];
	}

	public double[][] getMatrix() { return matrix; }

	void randomize () {
		for (int y = 0; y < matrix.length; ++y) {
			for (int x = 0; x < matrix[y].length; ++x) {
				matrix[y][x] = 45000*Math.random(); 
			}
		}
	} 

	public Image getAsImage (boolean blackAndWhite, Component component) {
		// get min, max
		double minVal = Double.MAX_VALUE; 
		double maxVal = Double.MIN_VALUE;
		for (int y = 0; y < matrix.length; ++y) {
			for (int x = 0; x < matrix[y].length; ++x) {
				if (matrix[y][x] > maxVal)
					maxVal = matrix[y][x];
				if (matrix[y][x] < minVal)
					minVal = matrix[y][x];
			}
		}

		// scale & build image
		Image image = component.createImage (nCols, nRows);		
		Graphics imageGfx = image.getGraphics();
		double scaleFactor = 255 / (maxVal - minVal);
		for (int y = 0; y < nRows; ++y) {
			for (int x = 0; x < nCols; ++x) {
				int pixVal = (int) (scaleFactor * (matrix[y][x] - minVal));
				if (y > 10) 
					imageGfx.setColor (colorScale(pixVal, blackAndWhite));
				else
					imageGfx.setColor (colorScale((y*nRows+x)%256, blackAndWhite));
				imageGfx.drawLine (x,y,x,y);
			}
		}

		// return image
		return image;
	}

	private Color colorScale (int pixVal, boolean blackAndWhite) {
		if (blackAndWhite) {
			return new Color (pixVal,pixVal,pixVal);	
		} else {
			double r = ((double)pixVal) / 255.0;
			return new Color (
				///* Red   */ sat2 (r, 0.28,  0.66,   0, 63),
	   			///* Green */ sat2 (r, 0.66,  1.00,   0, 63),
	   			///* Blue  */ sat2 (r, 0.00,  0.28,  10, 63)
				/* Red   */ sat2 (r, 0.28,  0.66,   0, 255),
	   			/* Green */ sat2 (r, 0.66,  1.00,   0, 255),
	   			/* Blue  */ sat2 (r, 0.00,  0.28,  10, 255)
			); 
		}
	}

	private int sat2 (double x, double x1, double x2, double y1, double y2)
	{
		if (x1 >= x2) {
			throw new ArithmeticException ("sat2");
 		}
 		if (x <= x1)
			return (int)y1;
 		if (x >= x2)
   			return (int)y2;
 		double a = (y2 - y1) / (x2 - x1);
 		double b = (y1 * x2 - y2 * x1) / (x2 - x1);
 		return (int)(a * x + b);
	}

	public int getSquareDim () {
		if (nRows != nCols)
			return -1;
		return nRows;
	}
}

