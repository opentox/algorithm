import java.util.*;
import java.io.*;
import org.openscience.cdk.DefaultChemObjectBuilder;
import org.openscience.cdk.interfaces.IMolecule;
import org.openscience.cdk.io.iterator.IteratingMDLReader;
import org.openscience.cdk.qsar.*;
import org.openscience.cdk.qsar.DescriptorValue;

class CdkDescriptors {
  public static void main(String[] args) {

    // parse command line arguments (descriptors)
    DescriptorEngine engine;
    if (args.length > 0) {
      for (int i =0; i < args.length; i++) {
        args[i] = "org.openscience.cdk.qsar.descriptors.molecular." + args[i] + "Descriptor";
      }
      List<String> classNames = Arrays.asList(args);
      engine = new DescriptorEngine(classNames);
      List<IDescriptor> instances =  engine.instantiateDescriptors(classNames);
      List<DescriptorSpecification> specs = engine.initializeSpecifications(instances);
      engine.setDescriptorInstances(instances);
      engine.setDescriptorSpecifications(specs);
    } else {
      engine = new DescriptorEngine(DescriptorEngine.MOLECULAR);
    }

    // parse 3d sdf from stdin and calculate descriptors
    BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
    IteratingMDLReader reader = new IteratingMDLReader( br, DefaultChemObjectBuilder.getInstance());
    while (reader.hasNext()) {
      IMolecule molecule = (IMolecule)reader.next();
      try {
        engine.process(molecule);
        Iterator it = molecule.getProperties().values().iterator(); 
        Boolean first = true;
        while (it.hasNext()) {
          try {
            DescriptorValue value = (DescriptorValue)it.next();
            int size = value.getValue().length();
            if (size == 1) {
              if (first) { System.out.print("- "); }
              else { System.out.print("  "); }
              System.out.println(":"+value.getNames()[0].toString() + ": " + value.getValue());
              first = false;
            }
            else {
              String[] values = value.getValue().toString().split(",");
              for (int i = 0; i < size; i++) {
                if (first) { System.out.print("- "); }
                else { System.out.print("  "); }
                System.out.println(":"+value.getNames()[i].toString() + ": "  + values[i]);
                first = false;
              }
            }
          }
          catch (ClassCastException e) { } // sdf properties are stored as molecules properties (strings), ignore them
        }
      }
      catch (Exception e) {
        System.out.println("- {}");
        System.err.println(e.toString());
      }
    }
  }
}
