/* J2ME Studio diagnostic MIDlet. Copyright 2026 J2ME Studio contributors.
 * SPDX-License-Identifier: Apache-2.0. No commercial game resources.
 */
import javax.microedition.midlet.MIDlet;
import javax.microedition.lcdui.*;
import javax.microedition.rms.RecordStore;
import java.io.*;

public final class StudioDiagnosticsMIDlet extends MIDlet implements Runnable, CommandListener {
    private TestCanvas canvas;
    private int launches;
    private volatile int starts, pauses;
    private volatile boolean rmsOK;
    private String error = "";

    protected void startApp() {
        starts++;
        if (canvas != null) { canvas.repaint(); return; }
        try {
            RecordStore store = RecordStore.openRecordStore("StudioDiagnostic", true);
            if (store.getNumRecords() > 0) {
                DataInputStream input = new DataInputStream(new ByteArrayInputStream(store.getRecord(1)));
                launches = input.readInt();
                if (!"中文存档正常".equals(input.readUTF())) throw new IOException("UTF round trip");
                input.close();
            }
            launches++;
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            DataOutputStream output = new DataOutputStream(bytes);
            output.writeInt(launches);
            output.writeUTF("中文存档正常");
            output.close();
            byte[] data = bytes.toByteArray();
            if (store.getNumRecords() == 0) store.addRecord(data, 0, data.length);
            else store.setRecord(1, data, 0, data.length);
            store.closeRecordStore();
            rmsOK = true;
        } catch (Exception e) { error = e.toString(); }
        canvas = new TestCanvas();
        Command exit = new Command("退出测试", Command.EXIT, 1);
        canvas.addCommand(exit);
        canvas.setCommandListener(this);
        Display.getDisplay(this).setCurrent(canvas);
        if ("1".equals(System.getProperty("j2me.studio.smoke"))) new Thread(this).start();
    }

    protected void pauseApp() { pauses++; }
    protected void destroyApp(boolean unconditional) { }
    public void commandAction(Command command, Displayable displayable) { notifyDestroyed(); }

    public void run() {
        try {
            Thread.sleep(5000);
            boolean pass = rmsOK && canvas.paints > 0 && canvas.combo && canvas.pressed >= 2
                && canvas.released >= 2 && canvas.repeated > 0 && canvas.directionAfterFive && starts >= 2 && pauses >= 1;
            String json = "{\"pass\":" + pass + ",\"launches\":" + launches
                + ",\"rms\":" + rmsOK + ",\"paints\":" + canvas.paints
                + ",\"pressed\":" + canvas.pressed + ",\"released\":" + canvas.released
                + ",\"repeated\":" + canvas.repeated + ",\"combo\":" + canvas.combo
                + ",\"directionAfterFive\":" + canvas.directionAfterFive
                + ",\"starts\":" + starts + ",\"pauses\":" + pauses + "}";
            FileOutputStream out = new FileOutputStream(System.getProperty("app.save.root") + "/diagnostic-result.json");
            out.write(json.getBytes("UTF-8")); out.close();
            System.out.println("[Studio diagnostics] " + json);
            if (error.length() > 0) System.out.println("[Studio diagnostics] " + error);
            // Cold simulator screenshots can take longer than the diagnostic run.
            // Keep the actual Canvas visible until CI acknowledges its capture.
            // This branch runs only with the explicit smoke-test JVM property.
            File captureDone = new File(System.getProperty("app.save.root"), "diagnostic-capture-done");
            long deadline = System.currentTimeMillis() + 30000;
            while (!captureDone.exists() && System.currentTimeMillis() < deadline) Thread.sleep(100);
        } catch (Exception e) { e.printStackTrace(); }
        finally { notifyDestroyed(); }
    }

    private final class TestCanvas extends Canvas {
        volatile int paints, pressed, released, repeated;
        volatile boolean right, five, combo, fiveWasReleased, directionAfterFive;
        private String lastKey = "请按方向键、数字键和软键";
        protected void paint(Graphics graphics) {
            graphics.setColor(0x102030); graphics.fillRect(0, 0, getWidth(), getHeight());
            graphics.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_PLAIN, Font.SIZE_MEDIUM));
            graphics.setColor(0xffffff);
            String[] lines = {"J2ME Studio 中文测试", "你好，Java 手机游戏", "RMS 启动次数：" + launches,
                "存档：" + (rmsOK ? "正常" : "失败"), lastKey,
                "按下/松开：" + pressed + "/" + released,
                "长按重复：" + repeated, "组合按键：" + (combo ? "已收到" : "待测试"),
                "暂停/恢复：" + pauses + "/" + starts};
            for (int i = 0; i < lines.length; i++) graphics.drawString(lines[i], 8, 8 + i * 25, Graphics.TOP | Graphics.LEFT);
            paints++;
        }
        protected void keyPressed(int code) {
            pressed++; if (code == -4) right = true; if (code == 53) five = true;
            if (right && five) combo = true;
            lastKey = "按键码：" + code; repaint();
        }
        protected void keyReleased(int code) {
            released++; if (code == -4) right = false;
            if (code == 53) { five = false; fiveWasReleased = true; }
            repaint();
        }
        protected void keyRepeated(int code) {
            repeated++; if (code == -4 && fiveWasReleased && right) directionAfterFive = true;
            repaint();
        }
    }
}
