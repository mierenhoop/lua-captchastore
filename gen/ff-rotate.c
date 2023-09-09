#if 0
gcc -s -O2 -o ff-rotate -Wno-unused-result ff-rotate.c -lm
exit
#endif

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  unsigned char d[8];
} Pixel;

static unsigned char buf[16];
static int width,height;
static long long shearh,shearv;
static Pixel*pic;

#define TAU (6.283185307179586476925286766559005768394)
#define fatal(...) do { fprintf(stderr,__VA_ARGS__); exit(1); } while(0)

static void process(int x,int y) {
  // There is probably some rounding error?
  int xx=x-width/2;
  int yy=y-height/2;
  yy+=(xx*shearv)/width;
  xx-=(yy*shearh)/height;
  yy+=(xx*shearv)/width;
  xx+=width/2;
  yy+=height/2;
  while(xx<0) xx+=width;
  while(yy<0) yy+=height;
  fwrite(pic[(yy%height)*width+(xx%width)].d,1,8,stdout);
}

int main(int argc,char**argv) {
  int x,y;
  if(argc!=2 && argc!=3) fatal("Incorrect number of arguments\n");
  fread(buf,1,16,stdin);
  fwrite(buf,1,16,stdout);
  width=(buf[8]<<24)|(buf[9]<<16)|(buf[10]<<8)|buf[11];
  height=(buf[12]<<24)|(buf[13]<<16)|(buf[14]<<8)|buf[15];
  pic=malloc(width*height*sizeof(Pixel));
  if(!pic) fatal("Allocation failed\n");
  fread(pic,width,height<<3,stdin);
  if(argc==2) {
    shearh=sin(strtod(argv[1],0)*TAU/360.0)*(long long)width;
    shearv=tan(strtod(argv[1],0)*TAU/720.0)*(long long)height;
  } else {
    shearh=strtol(argv[1],0,0);
    shearv=strtol(argv[2],0,0);
  }
  for(y=0;y<height;y++) for(x=0;x<width;x++) process(x,y);
  return 0;
}
