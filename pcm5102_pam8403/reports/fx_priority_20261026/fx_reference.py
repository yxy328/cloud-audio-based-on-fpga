"""Sample-domain queue model; no RTL state, RAM addresses or clock schedule."""
from collections import deque
import json,math,random,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
FS=50_000_000/1024
def sat(x):return max(-32768,min(32767,x))
def tz(x,den):return x//den if x>=0 else -((-x)//den)
class Effects:
    def __init__(self):self.reset()
    def reset(self):
        self.previous_mask=0;self.previous_settings=0;self.lfo=0
        self.chorus=deque(maxlen=2048);self.delay=deque(maxlen=4096)
        self.filtered=0;self.capture_count=0;self.delay_hold=0;self.clear_reverb()
    def clear_reverb(self):
        self.lines=[deque([0]*n,maxlen=n) for n in (618,658,707,751,308,244)]
        self.phase=0;self.previous_input=0;self.reverb_hold=0
    def step(self,dry,mask,settings,mix):
        depth=settings&3;tap=(settings>>2)&3;feedback=(settings>>4)&3;decay=(settings>>6)&3
        old=self.previous_settings
        if ((mask^self.previous_mask)&1) or ((settings^old)&3):self.chorus.clear()
        dchange=bool(((mask^self.previous_mask)&2) or ((settings^old)&12))
        if dchange:self.delay.clear();self.filtered=0;self.capture_count=0;self.delay_hold=0
        if ((mask^self.previous_mask)&4) or ((settings^old)&192):self.clear_reverb()
        self.previous_mask=mask;self.previous_settings=settings
        wet=[min(8,(mix>>shift)&15) for shift in (0,4,8)]
        triangle=(self.lfo&32767) if self.lfo<32768 else 32767-(self.lfo&32767)
        modulation=triangle>>2 if depth==0 else triangle>>1 if depth==1 else triangle if depth==2 else triangle*2
        distance=1024+(modulation>>8);fraction=modulation&255
        first=self.chorus[-distance] if len(self.chorus)>=distance else 0
        second=self.chorus[-distance-1] if len(self.chorus)>distance else 0
        delayed=sat(first+tz((second-first)*fraction,256))
        self.chorus.append(dry);self.lfo=(self.lfo+1)&65535
        chorus=sat(dry+tz(delayed*wet[0],16)) if mask&1 else dry
        if tap==0:capture=True;self.capture_count=0;self.filtered=0
        elif dchange:
            capture=False;self.capture_count=1;self.filtered=tz(chorus,2 if tap==1 else 4)
        else:
            scale=2 if tap==1 else 4
            self.filtered=tz(chorus+(scale-1)*self.filtered,scale)
            capture=self.capture_count==[0,1,3,5][tap]
            self.capture_count=0 if capture else self.capture_count+1
        if capture:
            echo=self.delay[0] if len(self.delay)==4096 else 0
            self.delay.append(sat(tz(chorus if tap==0 else self.filtered,2)+tz(echo*[4,8,10,12][feedback],16)))
        else:echo=self.delay_hold
        self.delay_hold=echo
        delay=sat(chorus+tz(echo*wet[1],16)) if mask&2 else chorus
        update=self.phase==0 and mask&4
        self.phase^=1
        feed=tz(delay+self.previous_input,16);self.previous_input=delay
        if update:
            outs=[]
            for line in self.lines[:4]:
                z=line.popleft();outs.append(z);line.append(sat(feed+tz(z*[10,12,13,14][decay],16)))
            network=sat(tz(sum(outs),4))
            for line in self.lines[4:]:
                z=line.popleft();v=sat(network+tz(z,2));network=sat(z-tz(v,2));line.append(v)
            self.reverb_hold=network
        return sat(delay+tz(self.reverb_hold*wet[2],16)) if mask&4 else delay

def vectors(full=False):
    root=HERE/'functional';root.mkdir(exist_ok=True)
    model=Effects();count=0;phases=[]
    path=root/('vectors_full.txt' if full else 'vectors_smoke.txt')
    with path.open('w',encoding='ascii') as f:
        def phase(name,frames,mask,settings,mix,signal,reset=True):
            nonlocal count
            start=count
            for n in range(frames):
                do_reset=reset and n==0
                if do_reset:model.reset()
                dry=signal(n)
                expected=model.step(dry,mask,settings,mix)
                f.write(f'{int(do_reset)} {dry} {mask} {settings:02x} {mix:03x} {expected}\n');count+=1
            phases.append({'name':name,'start':start,'frames':frames,'mask':mask,'settings':settings,'mix':mix})
        rng=random.Random(20261026)
        if not full:
            for mask in range(8):phase(f'smoke{mask}',5500,mask,0x52,0x864,lambda n:rng.randrange(-32768,32768))
        else:
            for mask in range(8):
                settings=((mask&3)<<6)|(((mask+1)&3)<<4)|(((mask+2)&3)<<2)|(mask&3)
                phase(f'mask{mask}',30000,mask,settings,0x864,
                    lambda n:int(6500*math.sin(2*math.pi*440*n/FS)+2500*math.sin(2*math.pi*659.255*n/FS)))
            for preset in range(4):
                phase(f'reverb_impulse{preset}',120000,4,(preset<<6)|0x12,0x800,lambda n:32767 if n==0 else 0)
                phase(f'reverb_negative{preset}',120000,4,(preset<<6)|0x12,0x800,lambda n:-32767 if n==0 else 0)
            for tap in range(4):phase(f'delay_impulse{tap}',60000,2,0x50|(tap<<2),0x080,lambda n:20000 if n==0 else 0)
            phase('chorus_tone',65536,1,0x53,0x008,lambda n:int(12000*math.sin(2*math.pi*440*n/FS)))
            # Independently change every field, including masks and wet clamps.
            for n in range(50000):
                do_reset=n%4093==0
                if do_reset:model.reset()
                mask=(n//997)&7;settings=(n//1201)&255;mix=(n*53)&4095
                dry=[-32768,32767,-1,0,1,rng.randrange(-30000,30001)][n%6]
                expected=model.step(dry,mask,settings,mix)
                f.write(f'{int(do_reset)} {dry} {mask} {settings:02x} {mix:03x} {expected}\n');count+=1
            phases.append({'name':'dynamic_controls','start':count-50000,'frames':50000})
    (root/path.with_suffix('.json').name).write_text(json.dumps({'sample_rate':FS,'frames':count,'phases':phases},indent=2)+'\n',encoding='utf-8')
    print(path,count)
if __name__=='__main__':vectors('--full' in sys.argv)
