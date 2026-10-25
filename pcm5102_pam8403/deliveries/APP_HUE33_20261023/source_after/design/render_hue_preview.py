"""Render the actual Android View drawing code through a desktop Canvas adapter.

This is a layout preview, not a device screenshot. The adapter lives only in
build/hue_preview and is never compiled into the APK. Live values are fixtures.
"""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/hue_preview'
OUT=ROOT/'design/out/hue33'
STUBS={
'android/util/DisplayMetrics.java':'''package android.util;
public class DisplayMetrics { public float density=2; }''',
'android/content/res/Resources.java':'''package android.content.res;
public class Resources { public android.util.DisplayMetrics getDisplayMetrics(){return new android.util.DisplayMetrics();} }''',
'android/content/Context.java':'''package android.content;
public class Context { public android.content.res.Resources getResources(){return new android.content.res.Resources();} }''',
'android/view/View.java':'''package android.view;
public class View {
 public static final int IMPORTANT_FOR_ACCESSIBILITY_YES=1;
 private android.content.Context context;private int w,h;
 public View(android.content.Context c){context=c;}
 public void setImportantForAccessibility(int i){} public void setContentDescription(String s){} public void invalidate(){}
 public android.content.res.Resources getResources(){return context.getResources();}
 public int getWidth(){return w;} public int getHeight(){return h;}
 protected void onSizeChanged(int w,int h,int oldw,int oldh){} protected void onDraw(android.graphics.Canvas c){}
 public void layout(int width,int height){w=width;h=height;onSizeChanged(w,h,0,0);}
 public void draw(android.graphics.Canvas c){onDraw(c);}
}''',
'android/graphics/Typeface.java':'''package android.graphics;
public class Typeface {public static final int NORMAL=0;boolean bold;
 public static Typeface create(String name,int style){Typeface t=new Typeface();t.bold=name.contains("medium");return t;}}
''',
'android/graphics/Shader.java':'''package android.graphics;
public class Shader {public enum TileMode { CLAMP } }''',
'android/graphics/LinearGradient.java':'''package android.graphics;
public class LinearGradient extends Shader {
 java.awt.LinearGradientPaint value;
 public LinearGradient(float x,float y,float xx,float yy,int[] colors,float[] positions,TileMode mode){
  java.awt.Color[] c=new java.awt.Color[colors.length];float[] p=new float[c.length];
  for(int i=0;i<c.length;i++){c[i]=new java.awt.Color(colors[i],true);p[i]=positions==null?i/(c.length-1f):positions[i];}
  value=new java.awt.LinearGradientPaint(x,y,xx,yy,p,c);
 }
}''',
'android/graphics/Paint.java':'''package android.graphics;
public class Paint {
 public static final int ANTI_ALIAS_FLAG=1;public enum Align { LEFT,CENTER,RIGHT }
 int color;float size,width;Typeface type=Typeface.create("sans-serif",0);Align align=Align.LEFT;Shader shader;
 public Paint(int flags){} public void setColor(int c){color=c;} public void setShader(Shader s){shader=s;}
 public void setTextSize(float s){size=s;} public void setTypeface(Typeface t){type=t;}
 public void setTextAlign(Align a){align=a;} public void setStrokeWidth(float w){width=w;}
}''',
'android/graphics/Canvas.java':'''package android.graphics;
public class Canvas {
 private java.awt.Graphics2D g;private int w,h;
 private java.util.Stack<java.awt.Graphics2D> saved=new java.util.Stack<>();
 public Canvas(java.awt.image.BufferedImage image){g=image.createGraphics();w=image.getWidth();h=image.getHeight();
  g.setRenderingHint(java.awt.RenderingHints.KEY_ANTIALIASING,java.awt.RenderingHints.VALUE_ANTIALIAS_ON);
  g.setRenderingHint(java.awt.RenderingHints.KEY_TEXT_ANTIALIASING,java.awt.RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
 }
 private void apply(Paint p){g.setPaint(p.shader==null?new java.awt.Color(p.color,true):((LinearGradient)p.shader).value);}
 private void bounds(float x,float y,float xx,float yy){if(x<0||y<0||xx>w+.1f||yy>h+.1f||xx<x||yy<y)throw new AssertionError("View overflow: "+x+","+y+","+xx+","+yy);}
 public void drawRoundRect(float x,float y,float xx,float yy,float rx,float ry,Paint p){bounds(x,y,xx,yy);apply(p);g.fill(new java.awt.geom.RoundRectangle2D.Float(x,y,xx-x,yy-y,2*rx,2*ry));}
 public void drawLine(float x,float y,float xx,float yy,Paint p){bounds(x,y,xx,yy);apply(p);g.setStroke(new java.awt.BasicStroke(p.width));g.draw(new java.awt.geom.Line2D.Float(x,y,xx,yy));}
 public void drawText(String s,float x,float y,Paint p){
  apply(p);g.setFont(new java.awt.Font("Microsoft YaHei",p.type.bold?java.awt.Font.BOLD:java.awt.Font.PLAIN,1).deriveFont(p.size));
  java.awt.FontMetrics f=g.getFontMetrics();float width=f.stringWidth(s);
  if(p.align==Paint.Align.CENTER)x-=width/2;else if(p.align==Paint.Align.RIGHT)x-=width;
  bounds(x,y-f.getAscent(),x+width,y+f.getDescent());g.drawString(s,x,y);
 }
 public int save(){saved.push(g);g=(java.awt.Graphics2D)g.create();return saved.size();}
 public boolean clipRect(float x,float y,float xx,float yy){g.clip(new java.awt.geom.Rectangle2D.Float(x,y,xx-x,yy-y));return true;}
 public void restore(){g.dispose();g=saved.pop();}
}''',
'cn/fpga/score/HuePreview.java':'''package cn.fpga.score;
import java.awt.image.BufferedImage;import java.io.File;import java.math.BigInteger;import javax.imageio.ImageIO;
public class HuePreview {
 static LedFrame fixture(int kind)throws Exception{
  BigInteger n=BigInteger.ONE.shiftLeft(108);
  if(kind!=2)n=n.or(BigInteger.ONE.shiftLeft(104));
  int[] levels={2,5,12,24,31,27,20,16,12,9,6,4,3,2,1,0};
  for(int i=0;i<16;i++)n=n.or(BigInteger.valueOf(kind==1?0:kind==3?31:levels[i]).shiftLeft(i*5));
  n=n.or(BigInteger.valueOf(kind==1?0:42).shiftLeft(92)).or(BigInteger.valueOf(kind==1?0:20).shiftLeft(86)).or(BigInteger.valueOf(kind==1?0:56).shiftLeft(80));
  return LedFrame.parse("V,"+String.format("%028X",n));
 }
 public static void main(String[] args)throws Exception{
  File out=new File(args[0]);out.mkdirs();int count=0;
  for(int width:new int[]{240,252,280,320,360,412})for(int state=0;state<6;state++){
   SpectrumPreviewView v=new SpectrumPreviewView(new android.content.Context());v.layout(width*2,356*2);
   if(state>0)v.setFrame(fixture(state-1));
   if(state==5)v.setFrame(null);
   BufferedImage image=new BufferedImage(width*2,712,BufferedImage.TYPE_INT_ARGB);
   v.draw(new android.graphics.Canvas(image));
   ImageIO.write(image,"png",new File(out,width+"_"+state+".png"));count++;
  }
  System.out.println("PASS native View desktop layout: "+count+" captures, 240/252/280/320/360/412dp, waiting/live/zero/loading/full/stale; no drawing or text overflow");
 }
}'''
}

def main():
    for name,code in STUBS.items():
        path=BUILD/'src'/name
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(code,encoding='utf-8')
    classes=BUILD/'classes';classes.mkdir(parents=True,exist_ok=True)
    main=ROOT/'app/src/main/java/cn/fpga/score'
    sources=list((BUILD/'src').rglob('*.java'))+[main/name for name in ('SpectrumPreviewView.java','LedHue.java','LedFrame.java','LedState.java')]
    subprocess.run(['javac','--release','8','-Xlint:-options','-encoding','UTF-8','-d',str(classes),*map(str,sources)],check=True)
    subprocess.run(['java','-Djava.awt.headless=true','-cp',str(classes),'cn.fpga.score.HuePreview',str(OUT)],check=True)
    for w in (240,252,280,320,360,412):
        assert (OUT/f'{w}_0.png').read_bytes()==(OUT/f'{w}_5.png').read_bytes(), 'stale frame must clear'
    font=lambda size,bold=False:ImageFont.truetype('C:/Windows/Fonts/msyh'+('bd' if bold else '')+'.ttc',size)
    page=Image.new('RGB',(1240,970),'#f6f0f9');d=ImageDraw.Draw(page)
    d.text((48,30),'APP · 音量色环',font=font(38,True),fill='#241a2e')
    d.text((48,92),'沿用 33 档青蓝紫红配色，融入 LED 频谱与音源幅度。',font=font(23),fill='#75657f')
    for i,(state,title) in enumerate(((0,'等待设备数据'),(1,'实时预览 · 示例数据'))):
        x=48+i*590
        d.rounded_rectangle((x-12,150,x+552,844),radius=26,fill='#fffbff')
        d.text((x+10,172),title,font=font(24,True),fill='#241a2e')
        im=Image.open(OUT/f'360_{state}.png').resize((540,534),Image.Resampling.LANCZOS)
        page.paste(im,(x,224),im)
        d.text((x+10,784),'开启实时预览             停止预览',font=font(22),fill='#9343b0')
    d.text((48,882),'原生 View 绘图代码的桌面排版预览；右侧为协议夹具，非手机实机截图。',font=font(19),fill='#75657f')
    d.text((48,922),'断线 / 数据过期会清空读数；色环标尺保留。无需新增 FPGA 资源。',font=font(19),fill='#75657f')
    page.save(OUT/'app_hue33_preview.png')
    print('OK App hue preview and stale-state equality ->',OUT/'app_hue33_preview.png')

if __name__=='__main__':main()
