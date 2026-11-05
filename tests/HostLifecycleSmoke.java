// Apache-2.0. Tests Java lifecycle state only, without UIKit/native callbacks.
import javax.microedition.midlet.MIDlet;

public final class HostLifecycleSmoke extends MIDlet {
    private int starts, pauses;
    protected void startApp() { starts++; }
    protected void pauseApp() { pauses++; }
    protected void destroyApp(boolean unconditional) { }
    public static void main(String[] args) throws Exception {
        MIDlet.resetDestroyRequest();
        HostLifecycleSmoke test = new HostLifecycleSmoke();
        test.callStartApp();
        test.callPauseApp();
        if (!MIDlet.isPaused() || test.pauses != 1) throw new AssertionError("Pause state");
        test.callStartApp();
        if (MIDlet.isPaused() || test.starts != 2) throw new AssertionError("Resume state");
        test.notifyPaused();
        test.resumeRequest();
        if (!MIDlet.isResumeRequested() || MIDlet.isResumeRequested()) throw new AssertionError("One resume request");
        test.notifyPaused();
        test.resumeRequest();
        test.callStartApp();
        if (MIDlet.isResumeRequested()) throw new AssertionError("Do not deliver stale resume twice");
        System.out.println("PASS host lifecycle pause/resume flags");
    }
}
