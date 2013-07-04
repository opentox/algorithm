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
    List<String> classNames = new ArrayList<String>();
    for (int i =1; i < args.length; i++) {
      classNames.add("org.openscience.cdk.qsar.descriptors.molecular." + args[i] + "Descriptor");
    }
    engine = new DescriptorEngine(classNames);
    List<IDescriptor> instances =  engine.instantiateDescriptors(classNames);
    List<DescriptorSpecification> specs = engine.initializeSpecifications(instances);
    engine.setDescriptorInstances(instances);
    engine.setDescriptorSpecifications(specs);

    try {
      BufferedReader br = new BufferedReader(new FileReader(args[0]));
      PrintWriter yaml = new PrintWriter(new FileWriter(args[0]+"cdk.yaml"));
      // parse 3d sdf from file and calculate descriptors
      IteratingMDLReader reader = new IteratingMDLReader( br, DefaultChemObjectBuilder.getInstance());
      while (reader.hasNext()) {
        try {
          IMolecule molecule = (IMolecule)reader.next();
          engine.process(molecule);
          Map<Object,Object> properties = molecule.getProperties();
          Boolean first = true;
          for (Map.Entry<Object, Object> entry : properties.entrySet()) {
            try {
              if ((entry.getKey() instanceof DescriptorSpecification) && (entry.getValue() instanceof DescriptorValue)) {
                DescriptorSpecification property = (DescriptorSpecification)entry.getKey();
                DescriptorValue value = (DescriptorValue)entry.getValue();
                String[] values = value.getValue().toString().split(",");
                for (int i = 0; i < values.length; i++) {
                  if (first) { yaml.print("- "); first = false; }
                  else { yaml.print("  "); }
                  String cdk_class = property.getImplementationTitle();
                  String name = cdk_class.substring(cdk_class.lastIndexOf(".")+1).replace("Descriptor","");
                  yaml.println("Cdk." + name + "." + value.getNames()[i] + ": " + values[i]);
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
