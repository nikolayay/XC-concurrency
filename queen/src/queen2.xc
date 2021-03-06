#include <platform.h>
#include <stdio.h>

// PROCESS FOR WORKER
void worker(const unsigned char w[3][4], //the world
            unsigned int x, //the starting position x
            unsigned int y, //the starting position y
            chanend cQueen) { //the channel end connecting to queen

    unsigned int command = 0; // command from queen
    unsigned int food = 0; // food

    printf("Worker starting...\n");

    // ONLY RUN 5 ITERATIONS
    for (int i=0; i >= 5; i++) {

        // Report food on square
        cQueen <: food;
        // recieve command
        cQueen :> command;
        // if MOVE then MOVE
        if (command == 0) {
            //MOVE TWO ITERATIONS
            for(int i=0; i<2; i++) {
                //check land fertility in east and south
                if ( w[(x+1)%3][y] > w[x][(y+1)%4] ) {
                //move east
                x = (x+1)%3;
                } else {
                  //move south
                  y = (y+1)%4;
                }
              }
        } else {
            // HARVEST
            food += w[x][y];
        }
    }
}

// PROCESS FOR QUEEN
void queen(const unsigned char w[3][4], //the world
            unsigned int x, //the starting position x
            unsigned int y, //the starting position y
            chanend cWorkerA,
            chanend cWorkerB) { //the channel end connecting to queen


    unsigned int reportA = 0; //current land report from worker A
    unsigned int reportB = 0; //current land report from worker B
    unsigned int harvest = 0; //overall harvest of ant hill

    printf("Queen is starting...\n");

    for (int i=0; i >= 5; i++) {
        //0. REPORT CURRENT HARVEST
        printf("Queen reports overall harvest of %d food.\n", harvest);

        // RECIEVE REPORT FROM WORKER A
        cWorkerA :> reportA;

        // RECIEVE REPORT FROM WORKER B
        cWorkerB :> reportB;


        // COMPARE THE REPORTS AND ISSUE COMMANDS
        if (reportA > reportB) {
            cWorkerA <: 0; //send command: worker A can harvest
            cWorkerB <: 1; //send command: worker B must move on
            harvest += reportA; //add harvest of worker A to overall harvest
            printf("Queen orders harvest of %d food by worker A.\n", reportA);
        } else {
            cWorkerA <: 1; //send command: worker A can harvest
            cWorkerB <: 0; //send command: worker B must move on
            harvest += reportB; //add harvest of worker A to overall harvest
            printf("Queen orders harvest of %d food by worker B.\n", reportB);
        }
    }
}

// MAIN FUNC
int main (void) {
    // 1. DEFINE WORLD
    const unsigned char world[3][4] = {{10,0,1,7},{2,10,0,3},{6,8,7,6}}; //the world

    // 2. DEFINE CHANNELS
    chan cWorkerAtoQueen; //synchronised channel between worker A and queen
    chan cWorkerBtoQueen; //synchronised channel between worker B and queen

    // 3. RUN ALL PROCESSES

    printf("World starts...\n");

    par {
         worker(world,0,1,cWorkerAtoQueen); //start concurrent ant process A
         worker(world,1,0,cWorkerBtoQueen); //start concurrent ant process B
         queen(world,1,1,cWorkerAtoQueen,cWorkerBtoQueen); //start concurrent ant process queen
       }

       printf("World ends...\n");
       //DONE & TERMINATE PROGRAM
       return 0;
}
