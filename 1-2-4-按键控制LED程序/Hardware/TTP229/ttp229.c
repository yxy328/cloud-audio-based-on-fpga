#include "ttp229.h"
#include "delay.h"
#include "usart.h"

void TTP229_Init(void){
  
  //SDO  当ttp229接收到触摸后，向MCU发出接触信号
  GPIO_InitTypeDef  GPIO_InitStructure; 
  RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOB,ENABLE);       
  GPIO_InitStructure.GPIO_Pin = TTP229_SDO ;                        
  GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IPU;
  GPIO_Init(TTP229_PORT, &GPIO_InitStructure);	
  
  //SCL 当MCU接收到触摸信号后，向ttp229发送时序，读取键值
  GPIO_InitStructure.GPIO_Pin = TTP229_SCL ;                       
  GPIO_InitStructure.GPIO_Mode = GPIO_Mode_Out_PP;        
  GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz; 
	
  GPIO_Init(TTP229_PORT, &GPIO_InitStructure);	

  //当TP1=0,TP2=0时，应在SDO和SCL初始化时将电平拉低
  GPIO_ResetBits(TTP229_PORT,TTP229_SDO | TTP229_SCL);  
  
}

int ttp229_read(void){
  
  unsigned int num =0;
  unsigned int i=0;
  
  if(GPIO_ReadInputDataBit(TTP229_PORT,TTP229_SDO)){
  
    delay_us(120);//参考手册时序：DV+Tw>93us+10us
    
    for(i=0;i<16;i++){
      
      //参考手册时序：1kHz < F_SCL< 512 kHz  => 1.92us < f1+f0< 1ms , f1+f0:一个高电平+一个低电平时间和
      GPIO_SetBits(TTP229_PORT,TTP229_SCL);
      delay_us(300);
      GPIO_ResetBits(TTP229_PORT,TTP229_SCL);
      delay_us(300);
      
      if(GPIO_ReadInputDataBit(TTP229_PORT,TTP229_SDO)){
      
        num=i+1;
        //参考博文：https://blog.csdn.net/baidu_15814023/article/details/100580650
        //手册时序中 T_resp(for 16-KEYS) type(常用值)：32ms,但是并没有说 SDO 第二次主动向MCU发送数据时的高电平时长
        //参考博文文末的逻辑分析应该是两个相邻 SCL 上升时间间隔，即一个 F_SCL 
        delay_us(600);
       }
    }
  }
  return num;
}

//-------------------------配置引脚中断----------------------------
u8 INT_MARK;

void ttp229_INT_INIT(void){

  NVIC_InitTypeDef  NVIC_InitStruct;	//定义结构体变量
	EXTI_InitTypeDef  EXTI_InitStruct;

  RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOB,ENABLE); //启动GPIO时钟 （需要与复用时钟一同启动） 
	RCC_APB2PeriphClockCmd(RCC_APB2Periph_AFIO , ENABLE);//配置端口中断需要启用复用时钟

//第1个中断	
	GPIO_EXTILineConfig(GPIO_PortSourceGPIOB, GPIO_PinSource7);  //定义 GPIO  中断  
	
	EXTI_InitStruct.EXTI_Line=EXTI_Line7;  //定义中断线
	EXTI_InitStruct.EXTI_LineCmd=ENABLE;              //中断使能
	EXTI_InitStruct.EXTI_Mode=EXTI_Mode_Interrupt;     //中断模式为 中断
	EXTI_InitStruct.EXTI_Trigger=EXTI_Trigger_Rising;   //上升沿触发
	
	EXTI_Init(& EXTI_InitStruct);
	
	NVIC_InitStruct.NVIC_IRQChannel=EXTI9_5_IRQn;   //中断线     
	NVIC_InitStruct.NVIC_IRQChannelCmd=ENABLE;  //使能中断
	NVIC_InitStruct.NVIC_IRQChannelPreemptionPriority=2;  //抢占优先级 2
	NVIC_InitStruct.NVIC_IRQChannelSubPriority=2;     //子优先级  2
	NVIC_Init(& NVIC_InitStruct);

}

void  EXTI9_5_IRQHandler(void){
    
	if(EXTI_GetITStatus(EXTI_Line7)!=RESET){//判断某个线上的中断是否发生 
		INT_MARK=2;//标志位置1，表示有按键中断
		EXTI_ClearITPendingBit(EXTI_Line7);   //清除 LINE 上的中断标志位
	}         
}
























