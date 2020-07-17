package jmu;

import com.sun.tools.attach.AttachNotSupportedException;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.lang.management.RuntimeMXBean;
import java.net.MalformedURLException;
import javax.management.AttributeNotFoundException;
import javax.management.InstanceNotFoundException;
import javax.management.JMException;
import javax.management.MBeanException;
import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;
import javax.management.ReflectionException;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;

/**
 *
 * @author Ruslan Synytsky
 */
public class MemoryUsageCollector {

    /**
     * @param args the command line arguments
     * @throws javax.management.MalformedObjectNameException
     * @throws java.net.MalformedURLException
     * @throws javax.management.MBeanException
     * @throws javax.management.AttributeNotFoundException
     * @throws javax.management.InstanceNotFoundException
     * @throws javax.management.ReflectionException
     * @throws com.sun.tools.attach.AttachNotSupportedException
     */
    public static void main(String[] args) throws MalformedObjectNameException, MalformedURLException, IOException, MBeanException, AttributeNotFoundException, InstanceNotFoundException, ReflectionException, JMException, AttachNotSupportedException {
        boolean human = false;
        String host = "localhost";
        int port = 10239;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("-human")) {
                human = true;
            } else if (args[i].startsWith("-p=")) {
                port = Integer.parseInt(args[i].substring(3));
            } else if (args[i].startsWith("-h=")) {
                host = args[i].substring(3);
            }
        }
        //HashMap map = new HashMap();
        //map.put("jmx.remote.credentials", credentials);
        JMXConnector c = JMXConnectorFactory.newJMXConnector(createConnectionURL(host, port), null);
        c.connect();
        MBeanServerConnection mbsc = c.getMBeanServerConnection();

        RuntimeMXBean run = ManagementFactory.getPlatformMXBean(mbsc, RuntimeMXBean.class);
        if (human) {
            System.out.println("Command Line Options");
        }
        System.out.print(run.getInputArguments() + "|");
        MemoryMXBean mem = ManagementFactory.getPlatformMXBean(mbsc, MemoryMXBean.class);
        int mb = 1024 * 1024;
        MemoryUsage heap = mem.getHeapMemoryUsage();
        if (human) {
            System.out.println();
            System.out.print("Heap: Init|Used|Commited|Max");
        }
        System.out.print(heap.getInit() / mb + "|" + heap.getUsed() / mb + "|" + heap.getCommitted() / mb + "|" + heap.getMax() / mb + "|");
        MemoryUsage nonHeap = mem.getNonHeapMemoryUsage();
        if (human) {
            System.out.println();
            System.out.print("Non Heap: Init|Used|Commited|Max");
        }
        System.out.print(nonHeap.getInit() / mb + "|" + nonHeap.getUsed() / mb + "|" + nonHeap.getCommitted() / mb + "|" + nonHeap.getMax() / mb + "|");

        ObjectName gcName = new ObjectName(ManagementFactory.GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE + ",*");
        String gcNames = "";
        for (ObjectName name : mbsc.queryNames(gcName, null)) {
            GarbageCollectorMXBean gc = ManagementFactory.newPlatformMXBeanProxy(mbsc,
                    name.getCanonicalName(),
                    GarbageCollectorMXBean.class);
            gcNames += "," + gc.getName();
        }
        System.out.print(gcNames.substring(1) + "|");
        System.out.print(execute("vmNativeMemory", "summary"));
    }

    private static JMXServiceURL createConnectionURL(String host, int port) throws MalformedURLException {
        return new JMXServiceURL("rmi", "", 0, "/jndi/rmi://" + host + ":" + port + "/jmxrmi");
    }

    public static String execute(String command, String... args) throws JMException {
        return (String) ManagementFactory.getPlatformMBeanServer().invoke(
                new ObjectName("com.sun.management:type=DiagnosticCommand"),
                command,
                new Object[]{args},
                new String[]{"[Ljava.lang.String;"});
    }

    public static String readInputStreamAsString(InputStream in) throws IOException {
        BufferedInputStream bis = new BufferedInputStream(in);
        ByteArrayOutputStream buf = new ByteArrayOutputStream();

        byte b[] = new byte[256];
        int n;
        boolean messagePrinted = false;
        do {
            n = in.read(b);
            if (n > 0) {
                String s = new String(b, 0, n, "UTF-8");
                System.out.print(s);
                messagePrinted = true;
            }
        } while (n > 0);
        if (!messagePrinted) {
            System.out.println("Command executed successfully");
        }
        return buf.toString("UTF-8");
    }
}
