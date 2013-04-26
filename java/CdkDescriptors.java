import java.util.*;
import java.io.*;
import org.openscience.cdk.DefaultChemObjectBuilder;
import org.openscience.cdk.interfaces.IMolecule;
import org.openscience.cdk.io.iterator.IteratingMDLReader;
import org.openscience.cdk.qsar.*;
import org.openscience.cdk.qsar.DescriptorValue;

class CdkDescriptors {
  public static void main(String[] args) {

    // parse command line arguments > 1 (descriptors)
    DescriptorEngine engine;
    if (args.length > 1) {
      List<String> classNames = new ArrayList<String>();
      for (int i =1; i < args.length; i++) {
        classNames.add("org.openscience.cdk.qsar.descriptors.molecular." + args[i] + "Descriptor");
      }
      engine = new DescriptorEngine(classNames);
      List<IDescriptor> instances =  engine.instantiateDescriptors(classNames);
      List<DescriptorSpecification> specs = engine.initializeSpecifications(instances);
      engine.setDescriptorInstances(instances);
      engine.setDescriptorSpecifications(specs);
    } else {
      engine = new DescriptorEngine(DescriptorEngine.MOLECULAR);
    }

    try {
      BufferedReader br = new BufferedReader(new FileReader(args[0]));
      PrintWriter yaml = new PrintWriter(new FileWriter(args[0]+"cdk.yaml"));
      // parse 3d sdf from file and calculate descriptors
      IteratingMDLReader reader = new IteratingMDLReader( br, DefaultChemObjectBuilder.getInstance());
      while (reader.hasNext()) {
        try {
          IMolecule molecule = (IMolecule)reader.next();
          engine.process(molecule);
          Iterator it = molecule.getProperties().values().iterator();
          Boolean first = true;
          while (it.hasNext()) {
            try {
              DescriptorValue value = (DescriptorValue)it.next();
              int size = value.getValue().length();
              if (size == 1) {
                if (first) { yaml.print("- "); }
                else { yaml.print("  "); }
                yaml.println(":"+value.getNames()[0].toString() + ": " + value.getValue());
                first = false;
              }
              else {
                String[] values = value.getValue().toString().split(",");
                for (int i = 0; i < size; i++) {
                  if (first) { yaml.print("- "); }
                  else { yaml.print("  "); }
                  yaml.println(":"+value.getNames()[i].toString() + ": "  + values[i]);
                  first = false;
                }
              }
            }
            catch (ClassCastException e) { } // sdf properties are stored as molecules properties (strings), ignore them
            catch (Exception e) { e.printStackTrace(); } // output nothing to yaml
          }
        }
        catch (Exception e) {
          yaml.println("- {}");
          e.printStackTrace();
          continue;
        }
      }
      yaml.close();
    }
    catch (Exception e) { e.printStackTrace(); }
  }
}
