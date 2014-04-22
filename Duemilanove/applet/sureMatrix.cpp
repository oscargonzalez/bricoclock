/*
 * demo16x24.c - Arduino demo program for Holtek HT1632 LED driver chip,
 *            As implemented on the Sure Electronics DE-DP016 display board
 *            (16*24 dot matrix LED module.)
 * Nov, 2008 by Bill Westfield
 */

#include <Wire.h>  
#include <avr/pgmspace.h>
#include <string.h> //needed for strlen()
#include "c64font.h"
#include "ht1632.h"

/*
  Conexiones eeprom:
  eeprom pin      arduino pin
  1,2,3,4         gnd
  5               analog 4 (sda)
  6               analog 5 (scl)
  7               N/A
  8               Vcc
  
*/

// Define display size in pixels
#define BOOT_MESSAGE            "Oscar Gonzalez, Mayo 2010 - www.BricoGeek.com"
#define DISPLAY_WIDTH           128 // 4 Sure 0832 Modules x 4 = 128
#define DISPLAY_HEIGHT          8
#define CHAR_WIDTH              8
#define TEXT_BUFFER_SIZE	255 	// Define max text lenght for one message
#define SCROLL_INTERVAL		50	// Set the delay between scroll shift
#define EEPROM_ADDRESS          0x50
#define EEPROM_SIZE             1024    // Total memory size to store messages

// Used to ask the main clock for data
#define CONTROL_BYTE_DATE        2
#define CONTROL_BYTE_TEMP        3

#include "WProgram.h"
void writeEEPROM(int deviceaddress, unsigned int eeaddress, byte data );
byte readEEPROM(int deviceaddress, unsigned int eeaddress );
void ht1632_chipselect(byte chipno);
void ht1632_writebits (byte bits, byte firstbit);
void ht1632_chipfree(byte chipno);
static void ht1632_sendcmd (byte cs, byte command);
static void ht1632_senddata (byte cs, byte address, byte data);
void ht1632_clear(char cs);
void DrawStatixText(char *strText);
uint8_t revbits(uint8_t arg);
void ScrollScreen();
void ClearBuffer();
void FlipBuffer();
void MemoryDump();
void setup ();
void StoreNewMessages();
void GetNextMessage();
char *GetDataFromClock(char controlByte);
void loop ();
char framebuffer[DISPLAY_WIDTH+CHAR_WIDTH];
char temp_text[TEXT_BUFFER_SIZE];
int last_time=0;
char filled_columns=0;
char current_text_char=0;
char current_message=0; // This is the current memory message we are processing
int total_messages=0; // Total messages in memory (EEPROM)

/*
 * Set these constants to the values of the pins connected to the SureElectronics Module
 */
static const byte HT1632_CS[4] = {10,11,12,13}; // Define pins for chip select of each matrix
static const byte ht1632_data = 8;  // Data pin (pin 7)
static const byte ht1632_wrclk = 9; // Write clock pin (pin 5)

void writeEEPROM(int deviceaddress, unsigned int eeaddress, byte data ) {
  Wire.beginTransmission(deviceaddress);
  Wire.send((int)(eeaddress >> 8));   // MSB
  Wire.send((int)(eeaddress & 0xFF)); // LSB
  Wire.send(data);
  Wire.endTransmission();

  delay(5);
}

byte readEEPROM(int deviceaddress, unsigned int eeaddress ) {
  byte rdata = 0xFF;

  Wire.beginTransmission(deviceaddress);
  Wire.send((int)(eeaddress >> 8));   // MSB
  Wire.send((int)(eeaddress & 0xFF)); // LSB
  Wire.endTransmission();

  Wire.requestFrom(deviceaddress,1);

  if (Wire.available()) rdata = Wire.receive();

  return rdata;
}
                                                                     
void ht1632_chipselect(byte chipno)
{
  digitalWrite(chipno, 0);
}

/*
 * ht1632_writebits
 * Write bits (up to 8) to h1632 on pins ht1632_data, ht1632_wrclk
 * Chip is assumed to already be chip-selected
 * Bits are shifted out from MSB to LSB, with the first bit sent
 * being (bits & firstbit), shifted till firsbit is zero.
 */
void ht1632_writebits (byte bits, byte firstbit)
{
  while (firstbit) 
  {
    digitalWrite(ht1632_wrclk, LOW);
    if (bits & firstbit) {
      digitalWrite(ht1632_data, HIGH);
    }
    else {
      digitalWrite(ht1632_data, LOW);
    }
    digitalWrite(ht1632_wrclk, HIGH);
    firstbit >>= 1;
  }
}
 
void ht1632_chipfree(byte chipno)
{
  digitalWrite(chipno, 1);
}

static void ht1632_sendcmd (byte cs, byte command)
{
  ht1632_chipselect(HT1632_CS[cs]);  // Select chip
  ht1632_writebits(HT1632_ID_CMD, 1<<2);  // send 3 bits of id: COMMMAND
  ht1632_writebits(command, 1<<7);  // send the actual command
  ht1632_writebits(0, 1); 	/* one extra dont-care bit in commands. */
  ht1632_chipfree(HT1632_CS[cs]); //done
}

static void ht1632_senddata (byte cs, byte address, byte data)
{
  ht1632_chipselect(HT1632_CS[cs]);  // Select chip
  ht1632_writebits(HT1632_ID_WR, 1<<2);  // send ID: WRITE to RAM
  ht1632_writebits(address, 1<<6); // Send address
  ht1632_writebits(data, 1<<3); // send 4 bits of data
  ht1632_chipfree(HT1632_CS[cs]); // done
}

void ht1632_clear(char cs)
{
  for (byte i=0; i<64; i++)
    ht1632_senddata(cs, i, 0);  // clear the display!
  
}

// Draw center text. Max: 16 chars (More will be truncated)
// This will flip the buffer
void DrawStatixText(char *strText)
{
  int dots=0;
  int text_len = strlen(strText);
  int x;
  
  if (text_len > 16) { text_len=16; } // Limit text to 16 (entire matrix)
  
  // Calculate center
  x = 8 - (text_len/2);
  dots = x*8;
  
  for (int i=0; i<text_len ; i++)
  {
    
    for (int bits=0 ; bits<8 ; bits++)
    {
      framebuffer[dots] = pgm_read_byte_near(&font_8x8[strText[i]][bits]);
      dots++;
    }
  }
  
  FlipBuffer();
}

// Reverse bits
uint8_t revbits(uint8_t arg) { 
  uint8_t result=0;
  if (arg & (_BV(0))) result |= _BV(7); 
  if (arg & (_BV(1))) result |= _BV(6); 
  if (arg & (_BV(2))) result |= _BV(5); 
  if (arg & (_BV(3))) result |= _BV(4); 
  if (arg & (_BV(4))) result |= _BV(3); 
  if (arg & (_BV(5))) result |= _BV(2); 
  if (arg & (_BV(6))) result |= _BV(1); 
  if (arg & (_BV(7))) result |= _BV(0); 
  return result;
}

// Shift framebuffer data one time to left
void ScrollScreen()
{
  unsigned char col;
  if (filled_columns == 0) { return; } // Nothing to scroll

  // Shift frame buffer one pixel left.
  for(col=0; col<DISPLAY_WIDTH+8-1; col++) { framebuffer[col] = framebuffer[col+1]; }
  filled_columns--;
}

// Clear framebuffer
void ClearBuffer()
{
    for (int x=0 ; x<DISPLAY_WIDTH+8 ; x++) { framebuffer[x]=0; } 
}

// Flip buffer to the matrix
void FlipBuffer()
{
  int bits;
  byte dots;
  int addr;
  int x;
  
  int cs;
  
  for (x=0 ; x<DISPLAY_WIDTH ; x++)
  {

      // Get column data from frame buffer
      dots = framebuffer[x];    
      dots = revbits(dots);
      
      if ((x >= 0) && (x < 32)) { cs=0; }
      if ((x >= 32) && (x < 64)) { cs=1; }
      if ((x >= 64) && (x < 96)) { cs=2; }
      if (x >= 96) { cs=3; }

      // Upper char
      addr = (x<<1) + (0>>2);  // compute which memory word this is in
      ht1632_senddata(cs, addr, dots>>4);
    
      // Lower char
      addr = (x<<1) + (4>>2);  // compute which memory word this is in
      ht1632_senddata(cs, addr, dots);
      
  }
}

void MemoryDump()
{
  int i;
  char ch;
  Serial.println("Memory dump:");
  for (i=0 ; i<EEPROM_SIZE ; i++)
  {
    ch = readEEPROM(EEPROM_ADDRESS, i);
    if (ch > 0) { Serial.print(ch); }
  }
  Serial.println();
  Serial.println("Dump ok");
}

void setup ()  // flow chart from page 17 of datasheet
{
  int i, j;
  
  Serial.begin(9600);
  Wire.begin(); // For I2C
  
  //Serial.println("Matrix init");
  
  // Clock and Data
  pinMode(ht1632_wrclk, OUTPUT);
  pinMode(ht1632_data, OUTPUT);
  
  //writeEEPROM(EEPROM_ADDRESS, 0, 0); // 0 messages
  
  // Chip specific (each matrix)
  for (i=0 ; i<4 ; i++)
  {
      pinMode(HT1632_CS[i], OUTPUT);
      digitalWrite(HT1632_CS[i], HIGH); 	/* unselect (active low) */
      
      //digitalWrite(HT1632_CS[i], LOW);
      ht1632_sendcmd(i, HT1632_CMD_SYSDIS);        // Disable system
      ht1632_sendcmd(i, HT1632_CMD_COMS10);        // 8*32, PMOS drivers
      ht1632_sendcmd(i, HT1632_CMD_MSTMD); 	// Master Mode
      ht1632_sendcmd(i, HT1632_CMD_SYSON); 	// System on
      ht1632_sendcmd(i, HT1632_CMD_LEDON); 	// LEDs on
      
      ht1632_clear(i);

  }
  
  //Serial.println("HT1632 OK");
  
  total_messages = readEEPROM(EEPROM_ADDRESS, 0);
  //Serial.print("Total messages: "); Serial.println(total_messages, DEC);
  //MemoryDump();
  
  // Check EEPROM format
  // First byte tell how many message we have (0-253)
  // Since is probably don't have 253 messages, we check for control value to RESET/Format the EEPROM the very first time we boot up the matrix
  /*
  if (readEEPROM(EEPROM_ADDRESS, 0) != EEPROM_CONTROL_VAL)
  {
    Serial.println("EEPROM Erase...");
    for (i=0 ; i<1024 ; i++) { writeEEPROM(EEPROM_ADDRESS, i, 0); }
    writeEEPROM(EEPROM_ADDRESS, 0, 0); // No message stored
  }
  */
  
  DrawStatixText("BricoClock v1.0"); delay(1000); ClearBuffer();
    
  // Copy first message
  strcpy(temp_text, BOOT_MESSAGE);
  
  last_time = millis();
  
  //Serial.println("Init OK");
  
}

// Store new messages incoming from the serial port
void StoreNewMessages()
{
  
    char ch;
    int i=0;
    int current_memory_position=1; // Byte 0 reserved to store total messages available
    char str_tmp[16];
    
    memset(str_tmp, 0, 16);
  
    // Check if there are new messages incoming from the main clock
    if( Serial.available())
    {
      
        ClearBuffer();
        memset(str_tmp, 0, 16);
        Serial.read();
        Serial.print(1);
        
        int must_continue = 1;
      
        total_messages=0;
        //Serial.println("Incoming data...");
        while ((Serial.available()) || (must_continue == 1))
  	{
            while (!Serial.available()) {  } // Wait for mor data before continue
            
  	    ch = Serial.read();            
  
  	    //Serial.println(ch);
            if (current_memory_position < EEPROM_SIZE) // Prevent buffer overflow
            {
                //Serial.println(current_memory_position);
                writeEEPROM(EEPROM_ADDRESS, current_memory_position, ch);
                current_memory_position++;
                
                if (ch == '\n') // Carriage return is the end of the message
                { 
                  //Serial.print(i); Serial.println(" stored"); 
                  Serial.print(1); // ACK
                  delay(100); // Wait 100ms for more...
                  total_messages++; i++; 
                 
                  ClearBuffer();        
                  sprintf(str_tmp, "Feed title %d", total_messages);
                  DrawStatixText(str_tmp);
                  
                  
                }
                
                if (ch == '\r') { must_continue=0; } // Control byte is 1 (end of feed)
            }
            //else { Serial.println("EOF"); }
            
        }
        writeEEPROM(EEPROM_ADDRESS, 0, total_messages); // Store total messages
        //Serial.print(current_memory_position); Serial.println(" bytes stored");
        //Serial.print("Mensajes: "); Serial.println(total_messages, DEC);
        
        ClearBuffer();        
        sprintf(str_tmp, "(%d bytes)", current_memory_position);
        DrawStatixText(str_tmp); delay(1400);
        ClearBuffer();
        memset(temp_text, 0, TEXT_BUFFER_SIZE); // Clear text buffer first
        current_text_char=0;
        current_memory_position=1;
                  
        // DEBUG        
        //MemoryDump();
        
    }
}

// Get next message from memory
void GetNextMessage()
{
  int cr_count=0;
  int i, c = 0;
  char ch;
  
  memset(temp_text, 0, TEXT_BUFFER_SIZE); // Clear text buffer first
  
  if (total_messages == 0)
  {
    sprintf(temp_text, "No hay mensajes");
    return;
  }
  
  if (current_message <= total_messages)
  {
    //Serial.print("current_message: "); Serial.println(current_message);
    for (i=1 ; i<EEPROM_SIZE ; i++)
    {
      ch = readEEPROM(EEPROM_ADDRESS, i);
      if (ch == '\n') 
      { 
        
        //Serial.println(temp_text);
          
        if (cr_count > total_messages) { /*Serial.println("cr_count > total_messages (loop)");*/ current_message=0; return; } // No more messages available
        if (cr_count == current_message) // Is the message we want?
        {
            //Serial.println("Done!");
           return; // Done! 
        }
        else { /*Serial.println("next...");*/ memset(temp_text, 0, TEXT_BUFFER_SIZE); c=0; cr_count++; } // Next message...
        
      }
      else
      {
        temp_text[c] = ch; 
        c++;        
      }
    }
  }
  else { /*Serial.println("Loop msg (0)");*/ current_message=0; } // Loop all the messages
}

char *GetDataFromClock(char controlByte)
{
    char str[16];
    char i=0;
    char ch=0;
    
    memset(str, 0, 16);
    Serial.print(controlByte); // Ask for data

  delay(1000);
  
   while (Serial.available())
   {
     ch = Serial.read();
     
     if (ch == '\n')
     {
       //Serial.print(str);
       while (Serial.available()) { Serial.read(); }
       return str; // String is complete.
     }
     else
     {
       str[i] = ch; // Store next char
       i++;
     }
   }
   
}

char chr=0;
char tchr[50];
void loop ()
{

        int i=0;  
        char ch;
        char info_text[16];
        
        StoreNewMessages();
        
        if ( (millis()-last_time) >= SCROLL_INTERVAL)
        {
          //Serial.print("scroll - "); Serial.print(" filled: "); Serial.print(filled_columns, DEC); Serial.print("curchar: "); Serial.println(current_text_char, DEC);
        
          if (filled_columns == 0)
          {
          
                // More text remaining, get next character.
                if (current_text_char <= strlen(temp_text))
                {
	          for (unsigned char bits=0 ; bits<8 ; bits++)
		  {
	            framebuffer[DISPLAY_WIDTH+bits] = pgm_read_byte_near(&font_8x8[temp_text[current_text_char]][bits]);
		    filled_columns++;
		  }
                }
                else
                {
                  // Fill it blank
	          for (unsigned char bits=0 ; bits<8 ; bits++) { framebuffer[DISPLAY_WIDTH+bits] = 0; filled_columns++; }                  
                }
				 
	        // Increase to next char if avaliable
		if (current_text_char < strlen(temp_text)) { current_text_char++; }
                else 
                { 
                    if (current_text_char < (strlen(temp_text)+16)) { current_text_char++; }
                    else 
                    { 
                      memset(info_text, 0, 16);
                      // Next message here
                      DrawStatixText(GetDataFromClock(CONTROL_BYTE_DATE)); delay(2000); ClearBuffer();
                      
                      //sprintf(info_text, "+%d (%d %%)", random(15, 25), random(40, 80));
                      //DrawStatixText(info_text); delay(2000); ClearBuffer();
                      DrawStatixText(GetDataFromClock(CONTROL_BYTE_TEMP)); delay(2000); ClearBuffer();                      
                      
                      GetNextMessage();
                      
                      current_message++;
                      current_text_char=0; 
                    }
                }
	  }

	  last_time = millis();
	  ScrollScreen();
          // Draw buffer to display!
          FlipBuffer();

        }
    
}

int main(void)
{
	init();

	setup();
    
	for (;;)
		loop();
        
	return 0;
}

