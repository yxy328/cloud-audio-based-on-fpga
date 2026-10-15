#ifndef __TTP229_H
#define __TTP229_H

#include "sys.h"

#define TTP229_PORT       GPIOB
#define TTP229_SDO        GPIO_Pin_7
#define TTP229_SCL        GPIO_Pin_6

void TTP229_Init(void);
int ttp229_read(void);

void ttp229_INT_INIT(void);

#endif //__TTP229_H


