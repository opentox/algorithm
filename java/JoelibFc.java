import joelib2.example.FeatureCalculationExample;
import joelib2.feature.util.AtomPropertyDescriptors;
import joelib2.feature.util.SMARTSDescriptors;
import joelib2.io.BasicIOType;
import org.apache.log4j.Category;

public class JoelibFc
{
  private static Category logger = Category.getInstance(FeatureCalculationExample.class.getName());
  public static final int CONTINUE = 0;
  public static final int STOP = 1;
  public static final int STOP_USAGE = 2;
  private static final double[] RDF_SMOOTHINGFACTORS = { 1.0D, 5.0D, 25.0D, 150.0D };
  private static final String NUMERIC = ".numeric";
  private static final String NUMERIC_NORMALIZED = ".numeric.normalized";
  private boolean calculateAP = true;
  private boolean calculateBinarySMARTS = true;
  private boolean calculateCountSMARTS = false;
  private boolean calculateJCC = true;

  private boolean calculateSSKey = true;

  private AtomPropertyDescriptors calculatorAP = new AtomPropertyDescriptors();

  private SMARTSDescriptors calculatorSMARTS = new SMARTSDescriptors();
  private String inputFile;
  private BasicIOType inType;
  private boolean normalize = false;
  private String outputFile;
  private BasicIOType outType;
  private String[] smartsDescriptions = null;
  private String smartsFile;
  private String[] smartsPatterns = null;
  private String trueDescName = null;

  public JoelibFc(String paramString1, String paramString2)
  {
    FeatureCalculationExample localFeatureCalculationExample = new FeatureCalculationExample();
    String[] arrayOfString = new String[2];
    arrayOfString[0] = paramString1;
    arrayOfString[1] = paramString2;
    int i = localFeatureCalculationExample.parseCommandLine(arrayOfString);
    localFeatureCalculationExample.initializeSMARTS();
    localFeatureCalculationExample.calculateNumericDescriptors();
    localFeatureCalculationExample.calculateNormalization();
    localFeatureCalculationExample.calculateNominalDescriptors();
  }
}
