// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16               //image height
#define  IMWD 16                  //image width

// Must be power of 2
#define  NUM_WORKERS 8

#define  FARMHT IMHT/NUM_WORKERS
#define  ITERATIONS 100

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

// port to access xCore-200 buttons
on tile[0] : in port buttons = XS1_PORT_4E;
on tile[0] : out port leds = XS1_PORT_4F;

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
//      printf( "-%4.1d ", line[ x ] ); //show image values
    }
//    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// LEDS and Buttons
//
/////////////////////////////////////////////////////////////////////////////////////////

//DISPLAYS an LED pattern
//[[combinable]]
void showLEDs(out port p, chanend fromDistributor) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
               // send 0 for nothing
  while (1) {
    fromDistributor :> pattern;   //receive new pattern from visualiser
    p <: pattern;                //send pattern to LED port
  }
}

// LISTENS to BUTTON input
//[[combinable]]
void buttonListener(in port b, chanend toDistrubutor) {
    int r;
    while(1) {
        b when pinseq(15) :> r;
        b when pinsneq(15) :> r;
        if ((r==13) || (r==14) ) toDistrubutor <: r;
    }
}

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
    int FARMHT_GHOSTS = FARMHT + 2;
    i += a;
    while (i < 0) i += FARMHT_GHOSTS;
    while (i >= FARMHT_GHOSTS) i -= FARMHT_GHOSTS;
    return i;
}

// arg 1 (board) matches board type from distrubutor function
int total_alive(uchar board[NUM_WORKERS][FARMHT + 2][IMHT]) {
    int count = 0;
    for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
        for( int y = 0; y < FARMHT; y++ ) {   //go through all lines
            for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
               if (board[workerId][y][x] != 0) {
                   count+=1;
               }
            }
        }
    }
    return count;
}

// + 2 for ghost rows
int count_alive(uchar board[FARMHT+2][IMWD], int x, int y) {
    int k, l, count;
    count = 0;
    /* go around the cell */
    for (k=-1; k<=1; k++) for (l=-1; l<=1; l++)
        /* only count if at least one of k,l isn't zero */
        if (k || l) {
            if (board[y_add(y,k)][x_add(x,l)]) count++;
        }
    return count;
}


// + 2 for ghost rows
unsigned char calculateNextCellState(uchar board[FARMHT + 2][IMWD], int x, int y) {
    // 1.Count neighbours.
    int alive = count_alive(board, x, y);

    uchar bits;

    // 2. Apply rules. Build a new board and send message to display.
    if ( board[y][x] ) {
        if ( (alive > 3) || ( alive < 2 ) ) {
            // DEAD
            bits = 0x00;
        } else {
            // ALIVE
            bits = 0xFF;
        }
     } else {
        if ( alive == 3 ) {
            // ALIVE
            bits = 0xFF;
        } else {
            // DEAD
            bits = 0x00;
        }
     }

    return bits;
}


typedef interface i {
    void get(uchar board[FARMHT + 2][IMWD], int id);
    void process(uchar board[FARMHT + 2][IMWD], int id);
} i;

void worker(server interface i workerI, int worker_id) {
    uchar localBoard[FARMHT + 2][IMWD];
    uchar processed[FARMHT + 2][IMWD];

    int processing = 0;

    while(1) {
        select {
            case workerI.get(uchar board[FARMHT + 2][IMWD], int id):
                // return the processed board
                memcpy(board,processed,(FARMHT + 2)*IMWD*sizeof(uchar));
                processing = 0;
                break;

            case workerI.process(uchar board[FARMHT + 2][IMWD], int id):
                // make a local copy
                memcpy(localBoard,board,(FARMHT + 2) * IMWD * sizeof(uchar));
                processing = 1;
                break;


            }

        if (processing) {
            // iterate over board
            for (int y = 0; y < FARMHT; y++){
//                printf("Worker %d: Processing row %d\n", worker_id, y);
                for (int x = 0; x < IMWD; x++){
                    uchar nextCellState = calculateNextCellState(localBoard, x, y);
                    processed[y][x] = nextCellState;
                }
            }
        }
    }
}

void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromButtons, chanend toLeds, client interface i workerI[NUM_WORKERS])
{

  uchar val;

  // 3D array that stores area of board per worker
  // + 2 to accomodate ghost rows
  uchar board[NUM_WORKERS][FARMHT + 2][IMWD];

  // Timer and its values
  timer t;
  uint32_t start_time , end_time, paused_start_time, paused_end_time;
  uint32_t total_idle_time = 0;


  // Turn LED green for reading phase.
  toLeds <: 4;

  printf("Worker farm height: %d\n", FARMHT);

  // Copy the board from the read module
  for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
      for( int y = 0; y < FARMHT; y++ ) {     //go through all lines
          for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line

              //read the pixel value
              c_in :> val;

              // populate board in local memory
              board[workerId][y][x] = val;

          }
      }
  }

  toLeds <: 0;


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

  t :> start_time;
  printf("Timer started\n");

  // Repeatedly run processing on a board iteration.
  while(running && iterations < ITERATIONS) {
      // control distributor
      select {
          // stop processing
          case fromButtons :> buttonInput: {
              if(buttonInput == 13) {
                  running = 0;
              }
              break;
          }

          // pause processing
          case fromAcc :> tiltInput: {
              if (tiltInput == 0) {
                  printf("PAUSING\n");
                  // pause the timer accordingly
                  t :> paused_start_time;
                  printf("Timer paused\n");

                  // switch leds to red
                  toLeds <: 8;

                  // enter paused state
                  paused = 1;

                  // Most recent pause_start time - start time = time elasped since beginning.
                  uint32_t total_time = (paused_start_time - start_time) / 1000000;

                  printf("\n-------------INTERMEDIATE STATUS REPORT-----------------\n");
                  printf( "\n%d processing round(s) completed...\n", iterations );
                  printf( "\nTotal time elapsed since start: %u ms\n", total_time );
                  printf( "\nCurrent number of live cells: %d\n", total_alive(board) );
                  printf("\n--------------------------------------------------------\n");

              }
              break;
          }
          default : {
              break;
          }
      }

      // paused state
      while(paused) {
          printf("Processing paused\n");

          select {
              case fromAcc :> tiltInput: {
                  if(tiltInput == 1) {
                      printf("UNPAUSING\n");

                      // resume timer
                      t :> paused_end_time;
                      // Update total paused time after each potential pause
                      total_idle_time += ((paused_end_time - paused_start_time) / 1000000);
                      printf("Timer resumed\n");

                      // exit paused state
                      paused = 0;
                  }
                  break;
              }
          }
      }

      // processing state
      flicker = !flicker;
      toLeds <: flicker;
      iterations++;

      for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
          int nextWorkerId = ((workerId + 1) + NUM_WORKERS) % NUM_WORKERS;
          int prevWorkerId = ((workerId - 1) + NUM_WORKERS) % NUM_WORKERS;

          for (int x = 0; x < IMWD; x++) {
              // populate top ghost row
              board[workerId][FARMHT+1][x] = board[prevWorkerId][FARMHT-1][x];

              // populate bottom ghost row
              board[workerId][FARMHT][x]   = board[nextWorkerId][0][x];
          }
      }

      for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
          workerI[workerId].process(board[workerId], workerId);
      }

      for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
          workerI[workerId].get(board[workerId], workerId);
      }

  }

  // Send all pixels back.
  // Set LED to blue on output.
  t :> end_time;
  printf("Timer finished\n");
  toLeds <: 2;
  for (int workerId = 0; workerId < NUM_WORKERS; workerId++) {
      for (int y = 0; y < FARMHT; y++ ) {
            for(int x = 0; x < IMWD; x++) {
                c_out <: (uchar)(board[workerId][y][x]);
            }
        }
  }

  // 0x00 - black
  // 0xFF - white
  toLeds <: 16;

  // Timings
  uint32_t total_time, processing_time, idle_time;

  total_time = (end_time-start_time) / 1000000;
  idle_time = (paused_end_time-paused_start_time) / 1000000;
  processing_time = total_time - total_idle_time;


  printf("\n-------------FINAL STATUS REPORT-----------------\n");
  printf( "\n%d processing round(s) completed...\n", iterations );
  printf( "\nTotal time elapsed: %u ms\n", total_time );
  printf( "\nTime spent processing: %u ms\n", processing_time);
  printf( "\nTotal IDLE TIME elapsed: %u ms\n", total_idle_time );
  printf( "\nCurrent number of live cells: %d\n", total_alive(board) );
  printf("\n---------------------------------------------------\n");



}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[x];
    }
    _writeoutline( line, IMWD );
//    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    // pause if tilted
    } else {
        if (x<=-100) {
            tilted = tilted - 1;
            toDist <: 0;
        }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation
interface i workerI[8];

chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan buttonsToDistributor;
chan ledsToDistributor;

par {
    on tile [0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile [0]:orientation(i2c[0],c_control);          //client thread reading orientation data
    on tile [0]:DataInStream(infname, c_inIO);          //thread to read in a PGM image
    on tile [0]:DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    on tile [0]:buttonListener(buttons, buttonsToDistributor);
    on tile [0]:showLEDs(leds,ledsToDistributor);

    on tile [0]:distributor(c_inIO, c_outIO, c_control, buttonsToDistributor, ledsToDistributor, workerI);//thread to coordinate work on image
    on tile [1]:worker(workerI[0],0);
    on tile [1]:worker(workerI[1],1);
    on tile [1]:worker(workerI[2],2);
    on tile [1]:worker(workerI[3],3);
    on tile [1]:worker(workerI[4],4);
    on tile [1]:worker(workerI[5],5);
    on tile [1]:worker(workerI[6],6);
    on tile [1]:worker(workerI[7],7);


  }

  return 0;
}
