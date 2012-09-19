import java.io.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Arrays;
import java.util.Vector;
import java.util.Map;

import org.openscience.cdk.ChemFile;
import org.openscience.cdk.aromaticity.CDKHueckelAromaticityDetector;
import org.openscience.cdk.interfaces.IAtomContainer;
import org.openscience.cdk.interfaces.IChemFile;
import org.openscience.cdk.interfaces.IChemObject;
import org.openscience.cdk.interfaces.IMolecule;
import org.openscience.cdk.io.ISimpleChemObjectReader;
import org.openscience.cdk.io.ReaderFactory;
import org.openscience.cdk.qsar.DescriptorEngine;
import org.openscience.cdk.qsar.IDescriptor;
import org.openscience.cdk.qsar.IMolecularDescriptor;
import org.openscience.cdk.qsar.result.DoubleArrayResult;
import org.openscience.cdk.qsar.result.DoubleArrayResultType;
import org.openscience.cdk.qsar.result.DoubleResult;
import org.openscience.cdk.qsar.result.IDescriptorResult;
import org.openscience.cdk.qsar.result.IntegerArrayResult;
import org.openscience.cdk.qsar.result.IntegerArrayResultType;
import org.openscience.cdk.qsar.result.IntegerResult;
import org.openscience.cdk.tools.manipulator.AtomContainerManipulator;
import org.openscience.cdk.tools.manipulator.ChemFileManipulator;
import org.openscience.cdk.qsar.descriptors.molecular.IPMolecularLearningDescriptor;
import org.openscience.cdk.smiles.SmilesGenerator;

public class ApplyCDKDescriptors
{

  public ApplyCDKDescriptors(String inpath, String outpath, String descNamesStr) throws java.io.IOException 
  { 
    getDescriptorCSV(inpath,outpath,descNamesStr);
  }

	private static DescriptorEngine ENGINE = new DescriptorEngine(DescriptorEngine.MOLECULAR);

	private static int getSize(IMolecularDescriptor descriptor)
	{
		IDescriptorResult r = descriptor.getDescriptorResultType();
		if (r instanceof DoubleArrayResultType)
			return ((DoubleArrayResultType) r).length();
		else if (r instanceof IntegerArrayResultType)
			return ((IntegerArrayResultType) r).length();
		else
			return 1;
	}

	private static String getName(IDescriptor descriptor)
	{
		return ENGINE.getDictionaryTitle(descriptor.getSpecification()).trim();
	}

	//public static void main(String args[]) throws java.io.IOException 
	//{
	//	String inpath = "hamster_3d.sdf";
  //  String outpath = "hamster_desc.csv";
  //  getDescriptorCSV(inpath,outpath,"KappaShapeIndicesDescriptor");
	//}

 public static void getDescriptorCSV(String sdfInputPath, String csvOutputPath, String descNamesStr) throws java.io.IOException  {
    List<IMolecule> mols = readMolecules(sdfInputPath);
		System.out.println("read " + mols.size() + " compounds");
		List<IDescriptor> descriptors = ENGINE.getDescriptorInstances();
		System.out.println("found " + descriptors.size() + " descriptors");

    List<String> descNames = Arrays.asList(descNamesStr.split(","));
    ArrayList<String> colNames = new ArrayList<String>();
    ArrayList<Double[]> values = new ArrayList<Double[]>();
    for (IDescriptor desc : descriptors) {
      if (desc instanceof IPMolecularLearningDescriptor)
        continue;
      String tname = desc.getClass().getName();
      String[] tnamebits = tname.split("\\.");
      if (!descNames.contains(tnamebits[tnamebits.length-1]))
        continue;
      String[] colNamesArr = desc.getDescriptorNames();
      colNames.addAll(Arrays.asList(colNamesArr));
      List<Double[]> valuesList = computeLists(mols, (IMolecularDescriptor) desc);
      values.addAll(valuesList);
    }

    int ncol = values.size();
    int nrow = mols.size();
    FileWriter fstream = new FileWriter(csvOutputPath);
    BufferedWriter out = new BufferedWriter(fstream);
    out.write("SMILES,");
    for (int c=0; c<ncol; c++) {
      if (c!=0) out.write(",");
      out.write(colNames.get(c));
    }
    out.write("\n");
    for (int r=0; r<nrow; r++) {
      String smi = getSmiles(mols.get(r));
      out.write(smi + ",");
      for (int c=0; c<ncol; c++) {
        if (c!=0) out.write(",");
        out.write(""+values.get(c)[r]);
      }
      out.write("\n");
    }
    out.flush();
 }


 public static String getSmiles(IMolecule m)
  {
    Map<Object, Object> props = m.getProperties();
    for (Object key : props.keySet()) {
      if (key.toString().equals("STRUCTURE_SMILES") || key.toString().equals("SMILES"))
        return props.get(key).toString();
    }
    SmilesGenerator g = new SmilesGenerator();
    return g.createSMILES(m);
  }

	public static List<Double[]> computeLists(List<IMolecule> mols, IMolecularDescriptor desc )
	{
    //System.out.println("computing descriptor " + getName(desc));
    List<Double[]> values = computeDescriptors(mols, (IMolecularDescriptor) desc);
    return values;
	}

	public static List<IMolecule> readMolecules(String filepath)
	{
		Vector<IMolecule> mols = new Vector<IMolecule>();
		File file = new File(filepath);
		if (!file.exists())
			throw new IllegalArgumentException("file not found: " + filepath);
		List<IAtomContainer> list;
		try
		{
			ISimpleChemObjectReader reader = new ReaderFactory().createReader(new InputStreamReader(
					new FileInputStream(file)));
			if (reader == null)
				throw new IllegalArgumentException("Could not determine input file type");
			IChemFile content = (IChemFile) reader.read((IChemObject) new ChemFile());
			list = ChemFileManipulator.getAllAtomContainers(content);
			reader.close();
		}
		catch (Exception e)
		{
			e.printStackTrace();
			return null;
		}

		for (IAtomContainer iAtomContainer : list)
		{
			IMolecule mol = (IMolecule) iAtomContainer;
			mol = (IMolecule) AtomContainerManipulator.removeHydrogens(mol);
			try
			{
				AtomContainerManipulator.percieveAtomTypesAndConfigureAtoms(mol);
			}
			catch (Exception e)
			{
				e.printStackTrace();
			}
			try
			{
				CDKHueckelAromaticityDetector.detectAromaticity(mol);
			}
			catch (Exception e)
			{
				e.printStackTrace();
			}
			if (mol.getAtomCount() == 0)
				System.err.println("molecule has no atoms");
			else
				mols.add(mol);
		}
		return mols;
	}

	public static List<Double[]> computeDescriptors(List<IMolecule> mols, IMolecularDescriptor descriptor)
	{
		List<Double[]> vv = new ArrayList<Double[]>();

		for (int j = 0; j < getSize(descriptor); j++)
			vv.add(new Double[mols.size()]);

		for (int i = 0; i < mols.size(); i++)
		{
			if (mols.get(i).getAtomCount() == 0)
			{
				for (int j = 0; j < getSize(descriptor); j++)
					vv.get(j)[i] = null;
			}
			else
			{
				try
				{
					IDescriptorResult res = descriptor.calculate(mols.get(i)).getValue();
					if (res instanceof IntegerResult)
						vv.get(0)[i] = (double) ((IntegerResult) res).intValue();
					else if (res instanceof DoubleResult)
						vv.get(0)[i] = ((DoubleResult) res).doubleValue();
					else if (res instanceof DoubleArrayResult)
						for (int j = 0; j < getSize(descriptor); j++)
							vv.get(j)[i] = ((DoubleArrayResult) res).get(j);
					else if (res instanceof IntegerArrayResult)
						for (int j = 0; j < getSize(descriptor); j++)
							vv.get(j)[i] = (double) ((IntegerArrayResult) res).get(j);
					else
						throw new IllegalStateException("Unknown idescriptor result value for '" + descriptor + "' : "
								+ res.getClass());
				}
				catch (Throwable e)
				{
					System.err.println("Could not compute cdk feature " + descriptor);
					e.printStackTrace();
					for (int j = 0; j < getSize(descriptor); j++)
						vv.get(j)[i] = null;
				}
			}
			for (int j = 0; j < getSize(descriptor); j++)
				if (vv.get(j)[i] != null && (vv.get(j)[i].isNaN() || vv.get(j)[i].isInfinite()))
					vv.get(j)[i] = null;
		}

		return vv;
	}
}
