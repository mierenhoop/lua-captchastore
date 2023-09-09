CFLAGS=

CFLAGS+= -DFONT_NX=13 -DFONT_NY=3

CHARS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-=

all: a.out

tilemap.png:# gen-tilemap.sh
	#./gen-tilemap.sh
	convert -size 312x125 xc:white \
		-pointsize 40 -font "DejaVu-Sans-Mono" -fill black \
		-draw "text 0,35 '0123456789ABC' text 0,75 'DEFGHIJKLMNOP' text 0,115 'QRSTUVWXYZ+-='" \
		png:tilemap.png

tilemap.inc: tilemap.png
	xxd -i $< $@
	echo "$(CHARS)" | awk 'END { print "int font_idx(char c) {\n\tswitch (c) {"; \
	for (i=0;i<length;i++) \
	  print "\tcase '\''" substr($$1,i+1,1) "'\'': return " i ";"; \
	print "\tdefault: return 0;\n\t}\n}" }' >> $@

main.c: tilemap.inc

a.out: main.c lodepng.c
	$(CC) $(CFLAGS) -o $@ $^ -lm

.PHONY: clean

clean:
	rm -f a.out tilemap.inc tilemap.png
