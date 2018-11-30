// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include "dataIO.xc"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width


// port to access xCore-200 buttons
on tile[0] : in port buttons = XS1_PORT_4E;

// port to access xCore-200 leds
on tile[0] : out port leds = XS1_PORT_4F;

// Interfaces
typedef interface i {
    void echo ( int x , int y );
} i;

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////

/* add to a width index, wrapping around like a cylinder */
int x_add (int i, int a) {
    i += a;
    while (i < 0) i += IMWD;
    while (i >= IMWD) i -= IMWD;
    return i;
}

/* add to a height index, wrapping around */
int y_add (int i, int a) {
    i += a;
    while (i < 0) i += IMHT;
    while (i >= IMHT) i -= IMHT;
    return i;
}

int count_alive(uchar board[IMWD][IMHT], int i, int j) {
    int k, l, count;
    count = 0;
    /* go around the cell */
    for (k=-1; k<=1; k++) for (l=-1; l<=1; l++)
        /* only count if at least one of k,l isn't zero */
        if (k || l) {
            if (board[x_add(i,k)][y_add(j,l)]) count++;
        }
    return count;
}

int total_alive(uchar board[IMWD][IMHT]) {
    int count = 0;

    for( int y = 0; y < IMHT; y++ ) {   //go through all lines
        for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
           if (board[x][y] != 0) {
               count+=1;
           }
        }
      }

    return count;

}

//DISPLAYS an LED pattern
int showLEDs(out port p, chanend fromDistributor) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
               // send 0 for nothing
  while (1) {
    fromDistributor :> pattern;   //receive new pattern from visualiser
    p <: pattern;                //send pattern to LED port
  }
  return 0;
}

// LISTENS to BUTTON input
void buttonListener(in port b, chanend toDistrubutor) {
    int r;
    while(1) {
        b when pinseq(15) :> r;
        b when pinsneq(15) :> r;
        if ((r==13) || (r==14) ) toDistrubutor <: r;
    }
}

void worker(server i distributor_worker_interface) {

}


void distributor(chanend c_in,
                 chanend c_out,
                 chanend fromAcc,
                 chanend fromButtons,
                 chanend toLeds,
                 client i distributor_worker_interface)
{
  int tilt;
  uchar val;
  uchar board[IMHT][IMWD];
  uchar next_board[IMHT][IMWD];

  // Timer and its values
  timer t;
  uint32_t start_time , end_time, paused_start_time, paused_end_time;
  uint32_t total_idle_time = 0;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> tilt;

  // Read in and do something with your image values..
  printf( "Processing...\n" );

  // Turn LED green for reading phase.
  toLeds <: 4;
  for( int j = 0; j < IMHT; j++ ) {   //go through all lines
    for( int i = 0; i < IMWD; i++ ) { //go through each pixel per line

        // (i-1, j-1) | (i-1, j) | (i-1, j+1)
        // (i, j-1)   | (i, j)   | (i, j+1)
        // (i+1, j-1) | (i+1, j) | (i+1, j+1)

        c_in :> val;//read the pixel value

        // populate board in local memory
        board[i][j] = val;

    }
  }
  toLeds <: 0;

  // iterate over board
  // 14 - SW1 - start processing
  // 13 - SW2 - export current state
  int buttonInput = 0;
  int tiltInput = 0;
  int paused = 0;
  int iterations = 0;
  int running = 1;
  int flicker = 0;

  printf("\nPress SW1 to start processing.\n");
  while(buttonInput != 14) {

      select {
          case fromButtons :> buttonInput: {
              break;
          }
          case fromAcc :> tiltInput: {
              continue;
          }
      }
      printf("Wrong button dumbass!\n");
  }

  // Overall timer starts
  t :> start_time;

  // Repeatedly run processing on a board iteration.
  while(running && iterations < 100) {
      // control distributor
      select {
          case fromButtons :> buttonInput: {
              if(buttonInput == 13) {
                  running = 0;
              }
              break;
          }
          case fromAcc :> tiltInput: {
              if (tiltInput == 0) {
                  printf("PAUSING\n");
                  // Paused timer starts
                  t :> paused_start_time;
                  printf("Timer paused\n");

                  // switch leds to red
                  toLeds <: 8;

                  // enter paused state
                  paused = 1;

                  // Difference between first timer and paused timer = time elasped since beginning.
                  uint32_t total_time = (paused_start_time - start_time) / 1000000;

                  printf("\n-------------INTERMEDIATE STATUS REPORT-----------------\n");
                  printf( "\n%d processing round(s) completed...\n", iterations );
                  printf( "\nTotal time elapsed since start: %u ms\n", total_time );
                  printf( "\nCurrent number of live cells: %d\n", total_alive(next_board) );
                  printf("\n--------------------------------------------------------\n");

              }
              break;
          }
          default : {
              break;
          }
      }

      while(paused) {
          printf("Processing paused\n");

          select {
              case fromAcc :> tiltInput: {
                  if(tiltInput == 1) {
                      printf("UNPAUSING\n");

                      // Get the paused time snapshot and calculate total time in pause
                      t :> paused_end_time;
                      total_idle_time += ((paused_end_time - paused_start_time) / 1000000);
                      printf("Timer resumed\n");

                      // exit paused state
                      paused = 0;
                  }
                  break;
              }
          }
      }


      // flips green led on/off each iteration
      flicker = !flicker;
      toLeds <: flicker;

      iterations++;

      // printf("Running iteration number %d, iteration);

      // ----- PROCESSING BEGINS -----
      for (int y = 0; y < IMHT; y++ ) {
          for(int x = 0; x < IMWD; x++) {
              // 1.Count neighbours.
              int alive = count_alive(board, x, y);

              // 2. Apply rules. Build a new board (next_board) and send message to display.
              if ( board[x][y] )
              {
                  if ( (alive > 3) || ( alive < 2 ) ) {
                      // DEAD
                      next_board[x][y] = 0x00;
                  } else {
                      // ALIVE
                      next_board[x][y] = 0xFF;
                  }
               } else {
                  if ( alive == 3 ) {
                      // ALIVE
                      next_board[x][y] = 0xFF;
                  } else {
                      // DEAD
                      next_board[x][y] = 0x00;
                  }
               }
            }
          }

      // Copy board for next iteration.
      for (int y = 0; y < IMHT; y++ ) {
          for(int x = 0; x < IMWD; x++) {
              board[x][y] = next_board[x][y];
          }
        }

      // ----- PROCESSING FINISHES -----
  }

  // Send all pixels back.
  // Set LED to blue on output.
  t :> end_time;
  printf("Timer finished\n");
  toLeds <: 2;
  for (int y = 0; y < IMHT; y++ ) {
      for(int x = 0; x < IMWD; x++) {
          c_out <: (uchar)(next_board[x][y]);
      }
  }
  // 0x00 - black
  // 0xFF - white
  toLeds <: 16;

  // Timings
  uint32_t total_time, processing_time, idle_time;

  total_time = (end_time-start_time) / 1000000;
  processing_time = total_time - total_idle_time;


  printf("\n-------------FINAL STATUS REPORT-----------------\n");
  printf( "\n%d processing round(s) completed...\n", iterations );
  printf( "\nTotal time elapsed: %u ms\n", total_time );
  printf( "\nTime spent processing: %u ms\n", processing_time);
  printf( "\nTotal IDLE TIME elapsed: %u ms\n", total_idle_time );
  printf( "\nCurrent number of live cells: %d\n", total_alive(next_board) );
  printf("\n---------------------------------------------------\n");

}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////


int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan buttonsToDistributor;
chan ledsToDistributor;

interface i distributor_worker_interface;

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);          //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control, buttonsToDistributor, ledsToDistributor, distributor_worker_interface);//thread to coordinate work on image
    worker(distributor_worker_interface);
    buttonListener(buttons, buttonsToDistributor);
    showLEDs(leds,ledsToDistributor);
  }

  return 0;
}
