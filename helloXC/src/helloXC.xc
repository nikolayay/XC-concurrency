/*
 * helloXC.xc
 *
 *  Created on: 5 Oct 2018
 *      Author: nikolay
 */
#include <stdio.h>
#include <partc.c>
#include <platform.h>

extern void hello(int a);

int main(void) {
    par {
        on tile[0] : hello(1);
        on tile[1] : hello(0);
    }
    return 0;
}

void delay(uint delay) {

    uint time, tmp;

    timer t;

    t :> time;

    t when timerafter (time + delay) :> tmp;

}
