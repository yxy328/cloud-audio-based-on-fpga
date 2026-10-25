"""Sample-domain queue model, independent of the RTL's RAM/FSM scheduling."""
from delivery import *
from collections import deque
import math, random

def sat(x): return max(-32768,min(32767,x))

class Model:
    def __init__(self):
        self.prev_mask=0;self.prev_tap=0;self.prev_preset=0;self.lfo=0
        self.chorus=deque(maxlen=2048);self.delay=deque(maxlen=4096)
        self.count=0;self.filtered=0;self.delay_hold=0
        self.reset_reverb()
    def reset_reverb(self):
        self.lines=[deque([0]*n,maxlen=n) for n in (618,658,707,751,308,244)]
        self.phase=0;self.previous_input=0;self.rev_hold=0
    def step(self,x,mask,wet,dt,rp):
        if (mask^self.prev_mask)&1:self.chorus.clear()
        dc=bool((mask^self.prev_mask)&2) or dt!=self.prev_tap
        if dc:self.delay.clear();self.count=0;self.filtered=0;self.delay_hold=0
        if (mask^self.prev_mask)&4 or rp!=self.prev_preset:self.reset_reverb()
        self.prev_mask=mask;self.prev_tap=dt;self.prev_preset=rp
        tri=((~self.lfo if self.lfo&32768 else self.lfo)&32767)>>8
        self.lfo=(self.lfo+1)&65535
        c=self.chorus[-(1024+tri)] if len(self.chorus)>=1024+tri else 0
        self.chorus.append(x)
        if mask&1:x=sat(x+((c*min(wet,8))>>4))
        if dt==0:cap=True;self.count=0;self.filtered=0
        elif dc:cap=False;self.count=1;self.filtered=x>>(1 if dt==1 else 2)
        else:
            self.filtered+=(x-self.filtered)>>(1 if dt==1 else 2)
            cap=self.count==(1,3,5)[dt-1]
            self.count=0 if cap else self.count+1
        if cap:
            self.delay_hold=self.delay[0] if len(self.delay)==4096 else 0
            self.delay.append(sat(((self.filtered if dt else x)>>1)+(self.delay_hold>>1)))
        if mask&2:x=sat(x+((self.delay_hold*min(wet,8))>>4))
        if self.phase==0 and mask&4:
            src=(x+self.previous_input)>>3
            taps=[line[0] for line in self.lines[:4]]
            for line,t in zip(self.lines[:4],taps):
                g=(t>>1)+(t>>(3 if rp==0 else 2))
                if rp>=2:g+=t>>(4 if rp==2 else 3)
                line.append(sat(src+g))
            net=sat(sum(t>>2 for t in taps))
            for line in self.lines[4:]:
                t=line[0];w=sat(net+(t>>1));line.append(w);net=sat(t-(w>>1))
            self.rev_hold=net
        self.phase^=1;self.previous_input=x
        return sat(x+((self.rev_hold*min(wet,8))>>4)) if mask&4 else x

label=sys.argv[1] if len(sys.argv)>1 else 'fx_proto'
out=HERE/'functional'/label;out.mkdir(parents=True,exist_ok=True)
vectors=[];expected=[];model=Model();rng=random.Random(2356)
for mask in range(8):
    model=Model()
    for n in range(30000):
        x=round(1000*math.sin(n*0.11)+1300*math.sin(n*0.021))
        if n in (10,18000):x=32767
        if n in (11,18001):x=-32768
        row=(mask,8,mask%4,mask%4,x,int(n==0))
        vectors.append(row);expected.append(model.step(x,*row[:4]))
for block in range(64):
    mask=block%8;wet=block%10;dt=(block//2)%4;rp=(block//3)%4
    for n in range(300):
        reset=int(block%19==0 and n==0)
        if reset:model=Model()
        x=rng.randint(-16000,16000)
        row=(mask,wet,dt,rp,x,reset);vectors.append(row);expected.append(model.step(x,*row[:4]))
(out/'vectors.txt').write_text(''.join(' '.join(map(str,r))+'\n' for r in vectors),encoding='ascii')
tb='''`timescale 1ns/1ps
module tb_fx_proto;
 reg clk=0,resetn=0,sv=0;always #10 clk=~clk;
 reg signed [15:0] dry=0;reg [2:0] mask=0;reg [3:0] wet=0;reg [1:0] dt=0,rp=0;
 wire signed [15:0] sample;wire valid,overrun;
 audio_fx_minproto dut(clk,resetn,sv,dry,mask,wet,dt,rp,sample,valid,overrun);
 integer f,g,rc,m,w,d,r,x,reset_flag,lat,n=0,maxlat=0;
 initial begin
  f=$fopen("VECTORS","r");g=$fopen("SAMPLES","w");
  repeat(3)@(negedge clk);resetn=1;
  while(!$feof(f))begin
   rc=$fscanf(f,"%d %d %d %d %d %d\\n",m,w,d,r,x,reset_flag);
   if(rc!=6)$fatal(1,"vector parse");
   if(reset_flag)begin resetn=0;repeat(2)@(negedge clk);resetn=1;end
   mask=m;wet=w;dt=d;rp=r;dry=x;sv=1;
   @(posedge clk);#1;lat=1;
   @(negedge clk);sv=0;
   while(!valid && lat<64)begin @(posedge clk);#1;lat=lat+1;end
   if(!valid || overrun)$fatal(1,"deadline/overrun");
   if(lat>maxlat)maxlat=lat;
   $fwrite(g,"%0d %0d\\n",sample,lat);n=n+1;
   repeat(2)@(negedge clk);
  end
  $fclose(g);$display("PASS prototype frames=%0d max_latency_inclusive=%0d overrun=0",n,maxlat);$finish;
 end
endmodule
'''.replace('VECTORS',(out/'vectors.txt').as_posix()).replace('SAMPLES',(out/'samples.txt').as_posix())
(HERE/'fixtures/tb_fx_proto.v').write_text(tb,encoding='utf-8')
command=['C:/iverilog/bin/iverilog.exe','-g2001','-s','tb_fx_proto','-o',str(out/'model.vvp'),
         str(HERE/'fixtures/tb_fx_proto.v'),str(HERE/label/'pcm5102_pam8403/src/audio_fx_minproto.v')]
with (out/'compile.log').open('w',encoding='utf-8') as f:r=subprocess.run(command,stdout=f,stderr=f)
if r.returncode:raise RuntimeError('Prototype compile failed')
with (out/'simulation.log').open('w',encoding='utf-8') as f:
    r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(out/'model.vvp')],stdout=f,stderr=f)
if r.returncode:raise RuntimeError((out/'simulation.log').read_text())
samples=[tuple(map(int,s.split())) for s in (out/'samples.txt').read_text().splitlines()]
errors=[(n,a[0],e,vectors[n]) for n,(a,e) in enumerate(zip(samples,expected)) if a[0]!=e]
result={'frames':len(samples),'expected_frames':len(expected),'error_count':len(errors),
        'first_errors':errors[:12],'max_latency_inclusive':max(s[1] for s in samples),
        'vector_sha256':sha(out/'vectors.txt'),'samples_sha256':sha(out/'samples.txt'),
        'covers_masks':list(range(8)),'covers_delay_and_reverb_presets':list(range(4)),
        'includes_reset_wet_clamp_extremes_and_configuration_changes':True,
        'not_legacy_effect_equivalence':True,'not_interpolated_chorus':True}
write_json(out/'results.json',result);print(json.dumps(result))
assert len(samples)==len(expected) and not errors
