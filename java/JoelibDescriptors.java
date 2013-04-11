import java.util.*;
import java.io.*;
import joelib2.feature.Feature;
import joelib2.feature.FeatureHelper;
import joelib2.feature.FeatureFactory;
import joelib2.feature.FeatureResult;
import joelib2.io.BasicIOType;
import joelib2.io.BasicIOTypeHolder;
import joelib2.io.BasicReader;
import joelib2.io.MoleculeFileHelper;
import joelib2.io.MoleculeFileIO;
import joelib2.io.MoleculeIOException;
import joelib2.molecule.BasicConformerMolecule;

class JoelibDescriptors {
  public static void main(String[] args) {

    // set args to all descriptors
    if (args.length == 0) {
      FeatureHelper helper = FeatureHelper.instance();
      args = (String[]) helper.getNativeFeatures().toArray(new String[0]);
    }

    FeatureFactory factory = FeatureFactory.instance();
    MoleculeFileIO loader = null;
    BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
    String line = new String();
    String sdf = new String();
    try {
      while ((line = br.readLine()) != null) { sdf += line + "\n"; }
      br.close();
      InputStream is = null;
      is = new ByteArrayInputStream(sdf.getBytes("UTF-8"));
      BasicIOType inType = BasicIOTypeHolder.instance().getIOType("SDF");
      loader = MoleculeFileHelper.getMolReader(is, inType);
      //BasicIOType outType = BasicIOTypeHolder.instance().getIOType("SMILES");
      //JOEMol mol = new JOEMol(inType, inType);
      BasicConformerMolecule mol = new BasicConformerMolecule(inType, inType);
      while (true) {
        try {
          Boolean success = loader.read(mol);
          if (!success) { break; }
          //System.err.println( mol );
          for (int i =0; i < args.length; i++) {
            Feature feature = factory.getFeature(args[i]);
            FeatureResult result = feature.calculate(mol);
            if (i == 0) { System.out.print("- "); }
            else { System.out.print("  "); }
            System.out.print( args[i]+": " );
            System.out.println( result.toString() );
          }

        }
        catch (Exception e) { 
      System.err.println(e.toString());
      e.printStackTrace();
      //next;
        }
      }
    }
    catch (Exception e) {
      e.printStackTrace();
      //System.err.println(e.toString());
    }
  }
}
