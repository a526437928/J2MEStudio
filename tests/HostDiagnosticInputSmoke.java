import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import javax.microedition.lcdui.Canvas;

/** Exercise the real diagnostic Canvas without substituting its input logic. */
public final class HostDiagnosticInputSmoke {
    private static Canvas fresh() throws Exception {
        Class<?> type = Class.forName("StudioDiagnosticsMIDlet$TestCanvas");
        Constructor<?> constructor = type.getDeclaredConstructor(StudioDiagnosticsMIDlet.class);
        constructor.setAccessible(true);
        return (Canvas) constructor.newInstance(new StudioDiagnosticsMIDlet());
    }
    private static boolean flag(Canvas canvas, String name) throws Exception {
        Field field = canvas.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.getBoolean(canvas);
    }
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        for (int direction : new int[] {Canvas.KEY_NUM6, Canvas.KEY_RIGHT}) {
            Canvas canvas = fresh();
            canvas.postKeyPressed(direction); canvas.postKeyPressed(Canvas.KEY_NUM5);
            require(flag(canvas, "combo"), "Right + 5 must recognise direction keycode " + direction);
            canvas.postKeyReleased(Canvas.KEY_NUM5); canvas.postKeyRepeated(direction);
            require(flag(canvas, "directionAfterFive"), "Right must remain held after releasing 5");
            canvas.postKeyReleased(direction);
            require(!flag(canvas, "right"), "Right must release");
        }
        Canvas reverse = fresh();
        reverse.postKeyPressed(Canvas.KEY_NUM5); reverse.postKeyPressed(Canvas.KEY_NUM6);
        require(flag(reverse, "combo"), "5 then right must also recognise a simultaneous hold");
        Canvas sequential = fresh();
        sequential.postKeyPressed(Canvas.KEY_NUM6); sequential.postKeyReleased(Canvas.KEY_NUM6);
        sequential.postKeyPressed(Canvas.KEY_NUM5);
        require(!flag(sequential, "combo"), "Sequential taps must not count as simultaneous");
        Canvas unrelated = fresh();
        unrelated.postKeyPressed(Canvas.KEY_NUM2); unrelated.postKeyPressed(Canvas.KEY_NUM5);
        require(!flag(unrelated, "combo"), "Up + 5 must not count as right + 5");
        Canvas aliases = fresh();
        aliases.postKeyPressed(Canvas.KEY_RIGHT); aliases.postKeyPressed(Canvas.KEY_NUM6);
        aliases.postKeyReleased(Canvas.KEY_RIGHT); aliases.postKeyPressed(Canvas.KEY_NUM5);
        require(flag(aliases, "combo"), "Releasing one right alias must not release another");
        aliases.postKeyReleased(Canvas.KEY_NUM5); aliases.postKeyRepeated(Canvas.KEY_NUM6);
        require(flag(aliases, "directionAfterFive"), "Repeat must survive another alias releasing");
        aliases.postKeyReleased(Canvas.KEY_NUM6);
        require(!flag(aliases, "right"), "All right aliases must release");
        System.out.println("PASS: diagnostic numeric/navigation right, order, release and negative cases");
    }
}
