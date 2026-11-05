package javax.microedition.lcdui;

/**
 * J2ME Font — delegates metrics to native CoreText via NativeBridge.
 * Analogous to J2ME-Loader's Font wrapping android.graphics.Paint + Typeface.
 */
public class Font {
    public static final int FACE_SYSTEM = 0;
    public static final int FACE_MONOSPACE = 32;
    public static final int FACE_PROPORTIONAL = 64;

    public static final int STYLE_PLAIN = 0;
    public static final int STYLE_BOLD = 1;
    public static final int STYLE_ITALIC = 2;
    public static final int STYLE_UNDERLINED = 4;

    public static final int SIZE_SMALL = 8;
    public static final int SIZE_MEDIUM = 0;
    public static final int SIZE_LARGE = 16;

    private final int face, style, size;
    private static final Font[] fonts = new Font[72];
    private volatile int cachedHeight = -1;
    private volatile int cachedAscent = -1;
    private String[] widthTexts;
    private int[] widths;
    private int nextWidth;

    private Font(int face, int style, int size) {
        this.face = face;
        this.style = style;
        this.size = size;
    }

    public static synchronized Font getFont(int face, int style, int size) {
        int faceIndex = face == FACE_SYSTEM ? 0 : face == FACE_MONOSPACE ? 1 : face == FACE_PROPORTIONAL ? 2 : -1;
        int sizeIndex = size == SIZE_SMALL ? 0 : size == SIZE_MEDIUM ? 1 : size == SIZE_LARGE ? 2 : -1;
        // Preserve the existing fallback for nonstandard vendor parameters.
        if (faceIndex < 0 || sizeIndex < 0 || style < 0 || style > 7) return new Font(face, style, size);
        int index = (faceIndex * 8 + style) * 3 + sizeIndex;
        if (fonts[index] == null) fonts[index] = new Font(face, style, size);
        return fonts[index];
    }

    public static Font getDefaultFont() {
        return getFont(FACE_SYSTEM, STYLE_PLAIN, SIZE_MEDIUM);
    }

    public int getFace() { return face; }
    public int getStyle() { return style; }
    public int getSize() { return size; }

    public boolean isPlain() { return style == STYLE_PLAIN; }
    public boolean isBold() { return (style & STYLE_BOLD) != 0; }
    public boolean isItalic() { return (style & STYLE_ITALIC) != 0; }
    public boolean isUnderlined() { return (style & STYLE_UNDERLINED) != 0; }

    public int getHeight() {
        if (cachedHeight < 0) cachedHeight = NativeBridge.measureFontHeight(face, style, size);
        return cachedHeight;
    }

    public int getBaselinePosition() {
        if (cachedAscent < 0) cachedAscent = NativeBridge.measureFontAscent(face, style, size);
        return cachedAscent;
    }

    public synchronized int stringWidth(String str) {
        if (str == null) throw new NullPointerException();
        if (str.length() == 0) return 0;
        if (widthTexts != null) {
            for (int i = 0; i < widthTexts.length; i++) if (str.equals(widthTexts[i])) return widths[i];
        }
        int width = NativeBridge.measureStringWidth(face, style, size, str);
        // Bounded per-font cache, so repeated HUD/menu labels need no new
        // CoreText layout each frame and large strings are not retained.
        if (str.length() <= 128) {
            if (widthTexts == null) { widthTexts = new String[16]; widths = new int[16]; }
            widthTexts[nextWidth] = str; widths[nextWidth] = width;
            nextWidth = (nextWidth + 1) % widthTexts.length;
        }
        return width;
    }

    public int charWidth(char ch) {
        return stringWidth(String.valueOf(ch));
    }

    public int charsWidth(char[] ch, int offset, int length) {
        return stringWidth(new String(ch, offset, length));
    }

    public int substringWidth(String str, int offset, int len) {
        return stringWidth(str.substring(offset, offset + len));
    }

    /**
     * Apply this immutable font to a native drawing context.
     * Called by Graphics when font changes.
     */
    void applyToContext(long ctx) {
        NativeBridge.setFont(ctx, face, style, size);
    }

    /**
     * Measure string width using the given native context.
     */
    int stringWidth(long ctx, String str) {
        return NativeBridge.getStringWidth(ctx, str);
    }
}
