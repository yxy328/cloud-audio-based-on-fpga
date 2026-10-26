from work import *
import math
root=HERE/'score_bend_alt';p=root/PROJECT.name
bench=(p/'sim/tb_score_bend_protocol.v').read_text(encoding='utf-8')
bench=bench.replace('"SONGBEND,1"','"ERR,CMD"')
bench=bench.replace('transact("SONG_BEGIN,2\\n",13,','transact("SONG_BEGIN,2,1\\n",15,')
extra=''
for command,expected in [('SONG_BEGIN,1,2','ERR,CMD'),('SONG_BEGIN,1,1','OK'),('SONG_CHORD,0,1,1,16384','OK'),('SONG_END','OK')]:
    extra+=f'        transact("{command}\\n",{len(command)+1},{{"{expected}",8\'d13,8\'d10}});\n'
bench=bench.replace('        transact("PING\\n",5,',extra+'        transact("PING\\n",5,')
(p/'sim/tb_score_bend_protocol.v').write_text(bench,encoding='utf-8')
vectors=HERE/'score_comparison_vectors.txt';count=0
with vectors.open('w',encoding='ascii') as out:
    def emit(r,lo,hi):
        global count
        if r!=0 and not 8192<=r<=32768:return
        expected=int(r!=0 and (r<lo or r>hi));out.write(f'{r} {lo} {hi} {expected}\n');count+=1
    for cents in range(50,1201,50):
        lo=round(16384*2**(-cents/1200));hi=round(16384*2**(cents/1200))
        for r in (0,*range(8192,32769)):emit(r,lo,hi)
    for lo in range(8192,15919):
        for r in (0,8192,lo-1,lo,lo+1,16383,16384,32768):emit(r,lo,32768)
    for hi in range(16864,32769):
        for r in (0,8192,16384,hi-1,hi,hi+1,32768):emit(r,8192,hi)
bench='''`timescale 1ns/1ps
module tb_score_compare;
reg clk=0;always #10 clk=~clk;
downloadable_song dut(.clk(clk),.resetn(1'b0));
reg [2047:0] path;integer fd,status,r,lo,hi,expected,count=0;
initial begin
 if(!$value$plusargs("vectors=%s",path))$fatal(1,"No vectors");fd=$fopen(path,"r");
 while(!$feof(fd))begin
   status=$fscanf(fd,"%d %d %d %d\\n",r,lo,hi,expected);if(status!=4)$fatal(1,"vector parse");
   if(dut.target_outside(r,lo,hi)!==expected[0])$fatal(1,"Compare r=%d lo=%d hi=%d",r,lo,hi);count=count+1;
 end
 $display("PASS domain-preserving narrowed target comparator: %0d reference pairs, all allowed targets and all lower/upper boundaries",count);$finish;
end
endmodule
'''
(p/'sim/tb_score_compare.v').write_text(bench,encoding='utf-8')
binary=HERE/'score_compare.vvp'
with (HERE/'score_compare.log').open('w',encoding='utf-8') as log:
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2001','-s','tb_score_compare','-o',str(binary),str(p/'sim/tb_score_compare.v'),str(p/'src/downloadable_song.v')],stdout=log,stderr=log,check=True)
    subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),'+vectors='+str(vectors)],stdout=log,stderr=log,check=True)
save(HERE/'score_compare_results.json',{'checked':count,'domain':'r=0 or8192..32768; lo8192..15918; hi16864..32768','passed':True})
print((HERE/'score_compare.log').read_text(encoding='utf-8'))
