#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

#include "lodepng.h"

#include "tilemap.inc"

uint64_t *g_font_data = NULL;
unsigned g_font_w, g_font_h;
unsigned g_font_px, g_font_py;

int captcha_init() {
    int err;
    err = lodepng_decode_memory((uint8_t**)&g_font_data, &g_font_w, &g_font_h,
            tilemap_png, tilemap_png_len, LCT_RGBA, 16);
    if (err != 0) {
        g_font_data = 0;
        fprintf(stderr, "lodepng error %d\n", err);
        return err;
    }

    g_font_px = g_font_w / FONT_NX;
    g_font_py = g_font_h / FONT_NY;

    return 0;
}


void captcha_free() {
    if (g_font_data) {
        free(g_font_data);
        g_font_data = 0;
    }
}

struct captcha_settings {
    int w, h;
    int shearv, shearh;
    int nch;
    int *ch;
};

static inline int clamp(int v, int max) {
    if (v > max) return max;
    return v;
}

size_t size;
uint64_t *d;
uint8_t *out;

int w = 290;
int h = 70;
int shearv = 0;
int shearh = 0;
const char *text = "ABCD";

void blit_char(char c, int dx, int dy) {
    int idx = font_idx(c);
    int sx = (idx % FONT_NX) * g_font_px;
    int sy = (idx / FONT_NX) * g_font_py;

    fprintf(stderr, "%d %d\n", sx, sy);

    for (int y = 0; y < g_font_py; y++) {
        for (int x = 0; x < g_font_px; x++) {
            if (dx+x>=w || dy+y>=h || dx+x<0 || dy+y<0) continue;
            d[(dy+y)*w+dx+x] = g_font_data[(y+sy)*g_font_w+x+sx];
            //int xx=x-g_font_px/2;
            //int yy=y-g_font_py/2;
            //yy+=(xx*shearv)/g_font_px;
            //xx-=(yy*shearh)/g_font_py;
            //yy+=(xx*shearv)/g_font_px;
            //xx+=g_font_px/2;
            //yy+=g_font_py/2;
            ////while(xx<0) xx+=s.w;
            ////while(yy<0) yy+=s.h;
            //if (xx < 0) xx = 0;
            //if (yy < 0) yy = 0;
            //d[(dy+y)*w+dx+x] = g_font_data[(sy+clamp(yy,g_font_py))*g_font_w+clamp(xx,g_font_px)+sx];
        }
    }
}

void line(int x1, int y1, int x2, int y2) {
    float m_A = y1 - y2;
    float m_B = x2 - x1;
    float m_C = x1 * y2 - x2 * y1;
    float c = sqrtf(m_A * m_A + m_B * m_B);
    float cmp = c * 1; // width
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if (fabs(m_A * x + m_B * y + m_C) < cmp) {
                d[y*w+x] = 0xffff0000ffffffff;
            }
        }
    }
}

void captcha_run() {
    blit_char('A', 0, 0);
    blit_char('-', 100, 0);

    for (int i = 0; i < 100; i++)
        line(i, 0, 10, 10);
}

int main() {
    captcha_init();

    size = 8*w*h;
    out = malloc(size);
    d = (uint64_t*)out;
    if (!out) {
        fputs("malloc failed\n", stderr);
        exit(1);
    }
    // make everything white
    memset(out, 0xff, size);

    captcha_run();

    fwrite("farbfeld", 1, 8, stdout);
    putchar(w>>24);
    putchar(w>>16);
    putchar(w>>8);
    putchar(w>>0);
    putchar(h>>24);
    putchar(h>>16);
    putchar(h>>8);
    putchar(h>>0);
    fwrite(out, w * h, 8, stdout);

    captcha_free();

    return 0;
}
