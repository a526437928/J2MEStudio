/* Self-authored pixel/metric regression fixture, Apache-2.0. */
package javax.microedition.lcdui;

public final class StudioFontChecks {
    private static final int WIDTH = 128, HEIGHT = 48, MARGIN = 4;
    public static int checks, exitWidth;
    public static boolean legacyClippingDetected;
    public static String error = "";

    private static void require(boolean condition, String label) {
        if (!condition) throw new RuntimeException(label);
        checks++;
    }

    private static int[] ink(Font font, String text, int x, int y, int anchor) {
        Image image = Image.createImage(WIDTH, HEIGHT);
        Graphics g = image.getGraphics();
        g.setColor(0xffffff); g.fillRect(0, 0, WIDTH, HEIGHT);
        g.setFont(font); g.setColor(0); g.drawString(text, x, y, anchor);
        int[] pixels = new int[WIDTH * HEIGHT];
        image.getRGB(pixels, 0, WIDTH, 0, 0, WIDTH, HEIGHT);
        int count = 0, left = WIDTH, right = -1, top = HEIGHT, bottom = -1;
        for (int row = 0; row < HEIGHT; row++) for (int col = 0; col < WIDTH; col++) {
            if ((pixels[row * WIDTH + col] & 0xffffff) != 0xffffff) {
                count++; left = Math.min(left, col); right = Math.max(right, col);
                top = Math.min(top, row); bottom = Math.max(bottom, row);
            }
        }
        return new int[] {count, left, right, top, bottom};
    }

    private static boolean sameShape(int[] first, int[] second) {
        return first[0] > 0 && first[0] == second[0]
            && first[2] - first[1] == second[2] - second[1]
            && first[4] - first[3] == second[4] - second[3];
    }

    public static boolean run() {
        checks = 0; error = "";
        try {
            Image contextImage = Image.createImage(WIDTH, HEIGHT);
            Graphics g = contextImage.getGraphics();
            for (int face : new int[] {Font.FACE_SYSTEM, Font.FACE_MONOSPACE})
            for (int style : new int[] {Font.STYLE_PLAIN, Font.STYLE_BOLD | Font.STYLE_ITALIC})
            for (int size : new int[] {Font.SIZE_SMALL, Font.SIZE_MEDIUM, Font.SIZE_LARGE}) {
                Font font = Font.getFont(face, style, size);
                int height = font.getHeight(), ascent = font.getBaselinePosition();
                require(height > 0 && ascent > 0 && ascent <= height, "Metrics before applying Graphics font");
                g.setFont(font);
                require(height == NativeBridge.getFontHeight(g.nativeContext), "Font and drawing height agree");
                require(ascent == NativeBridge.getFontAscent(g.nativeContext), "Font and drawing baseline agree");
                int measured = font.stringWidth("退出");
                require(measured == NativeBridge.getStringWidth(g.nativeContext, "退出") && measured > 0, "Chinese advance matches CoreText");
                require(font.charWidth('退') == NativeBridge.getStringWidth(g.nativeContext, "退"), "charWidth uses the same font");
                require(font.charsWidth(new char[] {'x', '退', '出', 'y'}, 1, 2) == measured, "charsWidth range");
                require(font.substringWidth("x退出y", 1, 2) == measured, "substringWidth range");
                require(font.stringWidth("") == 0, "Empty width");
                require(font.stringWidth("Wi 退出") == NativeBridge.getStringWidth(g.nativeContext, "Wi 退出"), "Mixed Latin/CJK width");
                g.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_PLAIN, size == Font.SIZE_LARGE ? Font.SIZE_SMALL : Font.SIZE_LARGE));
                require(font.stringWidth("退出") == measured && font.getHeight() == height, "Another context font cannot change this Font");
                int[] reference = ink(font, "退出", MARGIN, MARGIN, Graphics.TOP | Graphics.LEFT);
                require(reference[0] > 0, "Actual text pixels exist");
                int manualX = WIDTH - MARGIN - measured;
                int[] manual = ink(font, "退出", manualX, MARGIN, Graphics.TOP | Graphics.LEFT);
                require(sameShape(reference, manual) && manual[2] < WIDTH - MARGIN + 1, "Manual right alignment retains every glyph pixel");
                int[] right = ink(font, "退出", WIDTH - MARGIN, MARGIN, Graphics.TOP | Graphics.RIGHT);
                require(sameShape(manual, right) && manual[1] == right[1], "RIGHT anchor and measured LEFT position agree");
                int[] center = ink(font, "退出", MARGIN + measured / 2, MARGIN, Graphics.TOP | Graphics.HCENTER);
                require(sameShape(reference, center) && reference[1] == center[1], "HCENTER rounding agrees with Font width");
                int[] baseline = ink(font, "退出", MARGIN, MARGIN + ascent, Graphics.BASELINE | Graphics.LEFT);
                require(sameShape(reference, baseline) && reference[3] == baseline[3], "BASELINE and TOP positions agree");
                int[] bottom = ink(font, "退出", MARGIN, MARGIN + height, Graphics.BOTTOM | Graphics.LEFT);
                require(sameShape(reference, bottom) && reference[3] == bottom[3], "BOTTOM and Font height agree");
            }
            Font medium = Font.getDefaultFont();
            exitWidth = medium.stringWidth("退出");
            int[] full = ink(medium, "退出", MARGIN, MARGIN, Graphics.TOP | Graphics.LEFT);
            int[] oldPosition = ink(medium, "退出", WIDTH - MARGIN - "退出".length() * 8, MARGIN, Graphics.TOP | Graphics.LEFT);
            legacyClippingDetected = !sameShape(full, oldPosition);
            require(legacyClippingDetected, "Negative control detects the old eight-pixels-per-character crop");
            for (int i = 0; i < 24; i++) medium.stringWidth("菜单" + i);
            require(medium.stringWidth("退出") == exitWidth, "Bounded width cache remains correct after eviction");
            try { medium.stringWidth(null); require(false, "Null must throw"); }
            catch (NullPointerException expected) { checks++; }
            return true;
        } catch (Throwable failure) {
            error = failure.toString();
            System.out.println("[Font checks] " + error);
            return false;
        }
    }
}
