// Project-authored test, Apache-2.0. Runs on the host JDK, not the iOS JVM.
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import javax.microedition.rms.RecordStore;

public final class HostRmsSmoke {
    public static void main(String[] args) throws Exception {
        byte[] expected = args[1].getBytes(StandardCharsets.UTF_8);
        RecordStore store = RecordStore.openRecordStore("LaunchData", args[0].equals("write"));
        if (args[0].equals("write")) {
            int id = store.addRecord(new byte[] {0}, 0, 1);
            if (id != 1) throw new AssertionError("Unexpected first record ID");
            store.setRecord(id, expected, 0, expected.length);
        }
        if (store.getNumRecords() != 1 || !Arrays.equals(expected, store.getRecord(1))) {
            throw new AssertionError("RMS round trip mismatch");
        }
        store.closeRecordStore();
        System.out.println("PASS host RMS " + args[0]);
    }
}
