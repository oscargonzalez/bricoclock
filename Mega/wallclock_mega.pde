/****************************************************************************

	BricoClock
	Oscar Gonzalez - June 2009
	www.bricogeek.com
	
	Full post at:
	http://blog.bricogeek.com/noticias/tutoriales/bricoclock-reloj-gigante-casero-con-arduino/
	
	Pictures:
	http://www.flickr.com/photos/bricogeek/sets/72157625679655432/with/5295145224/	
	
	This is the main file for the board with Arduino Mega
	
	DISCLAMER
	=========

	Licensed under GNU General Public License v3

	http://creativecommons.org/licenses/by/3.0/

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
	INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
	PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
	FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
	OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
	DEALINGS IN THE SOFTWARE. 	
	
 ****************************************************************************/
 
#include <stdio.h>
#include <avr/wdt.h>
#include <EEPROM.h>
#include <Wire.h>
#include <Messenger.h>

/******************************************************************************************************************************************************************
  Internal Configuration an global variables
 ******************************************************************************************************************************************************************/
#define CLOCK_WELCOME		"WallClock by Oscar Gonzalez - www.BricoGeek.com"
#define CLOCK_FIRMWARE_VERSION	"1.0"
#define CLOCK_FIRMWARE_DATE	"June 2009"
#define DS1307_I2C_ADDRESS      0x68            // I2C Address for DS1307
#define CLOCK_TIME_UPDATE_RATE	1000		// Time update rate in miliseconds

#define CLOCK_DOT_1              47              // Dots!
#define CLOCK_DOT_2              49
#define CLOCK_DOT_3              51
#define CLOCK_DOT_4              53

// SHT15 Sensor
#define SHT15_CMD_TEMPERATURE    B00000011  // command used to read temperature 
#define SHT15_CMD_HUMIDITY       B00000101  // command used to read humidity 
#define SHT_CLOCK                2                        
#define SHT_DATA                 3   

// SAA1064 Display drivers
#define SAA1064_DRIVER1					0x70 >> 1
#define SAA1064_DRIVER2					0x76 >> 1
byte display_add1 = 0x70 >> 1;			        // left shit 1 bit the device addr to comply with Wire Lib
byte display_add2 = 0x76 >> 1;
/*
// Define serial commands to control the clock
#define COMMAND_OKEY            "OK" // Returned when return query is needed
#define COMMAND_ERROR           "KO" // Return when error (ie: 'Unknow command' 'or bad login')
#define COMMAND_GET_TEMP        'T' // Get temperature (Return XXX - Integer)
#define COMMAND_GET_HUMI        'H' // Get humidity (Return XX - Integer)
#define COMMAND_GET_TIME        'G' // Get time (Return HH:MM:SS)
#define COMMAND_SET_TIME        'S' // Set current time (Format: STHHMMSSDDMMYY) [ST-Hours-Minutes-Seconds-Day-Month-Year]
#define COMMAND_GET_DATE        'D' // Get time (Return DDMMYYYY)
*/
/* This is basically a "font" for the digits */
uint8_t digits_font[16] = {	0x3f, /* 0 */
			   	0x06, /* 1 */
				0x5b, /* 2 */
				0x4f, /* 3 */
				0x66, /* 4 */
				0x6d, /* 5 */
				0x7d, /* 6 */
				0x07, /* 7 */
				0x7f, /* 8 */
				0x6f, /* 9 */
};

// Global variables
unsigned long clock_sync=0;
byte second, minute, hour, dayOfWeek, dayOfMonth, month, year;
Messenger SerialMessage = Messenger(); 

void MsgParser();

/******************************************************************************************************************************************************************
  General utility functions
 ******************************************************************************************************************************************************************/
// Convert normal decimal numbers to binary coded decimal
byte decToBcd(byte val)
{
  return ( (val/10*16) + (val%10) );
}

// Convert binary coded decimal to normal decimal numbers
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
} 

/******************************************************************************************************************************************************************
  Realtime Clock DS1307
 ******************************************************************************************************************************************************************/
// 1) Sets the date and time on the ds1307
// 2) Starts the clock
// 3) Sets hour mode to 24 hour clock
// Assumes you're passing in valid numbers
// NOTE: Requires Wire library
void setDateDs1307(byte second,        // 0-59
                   byte minute,        // 0-59
                   byte hour,          // 1-23
                   byte dayOfWeek,     // 1-7
                   byte dayOfMonth,    // 1-28/29/30/31
                   byte month,         // 1-12
                   byte year)          // 0-99
{
   Wire.beginTransmission(DS1307_I2C_ADDRESS);
   Wire.send(0);
   Wire.send(decToBcd(second));    // 0 to bit 7 starts the clock
   Wire.send(decToBcd(minute));
   Wire.send(decToBcd(hour));      // If you want 12 hour am/pm you need to set
                                   // bit 6 (also need to change readDateDs1307)
   Wire.send(decToBcd(dayOfWeek));
   Wire.send(decToBcd(dayOfMonth));
   Wire.send(decToBcd(month));
   Wire.send(decToBcd(year));
   Wire.endTransmission();
}

// Gets the date and time from the ds1307
void getDateDs1307(byte *second,
          byte *minute,
          byte *hour,
          byte *dayOfWeek,
          byte *dayOfMonth,
          byte *month,
          byte *year)
{
  // Reset the register pointer
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0);
  Wire.endTransmission();

  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);

  // A few of these need masks because certain bits are control bits
  *second     = bcdToDec(Wire.receive() & 0x7f);
  *minute     = bcdToDec(Wire.receive());
  *hour       = bcdToDec(Wire.receive() & 0x3f);  // Need to change this if 12 hour am/pm
  *dayOfWeek  = bcdToDec(Wire.receive());
  *dayOfMonth = bcdToDec(Wire.receive());
  *month      = bcdToDec(Wire.receive());
  *year       = bcdToDec(Wire.receive());
}

// Initialize Realtime clock
void ds1307Init()
{  

  Serial.print("Realtime Clock init...");	
                                                     
  // Start 1HZ squarewave generator (used on interrupt INT0)
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0x07);
  Wire.send(B10010000);
  Wire.endTransmission();

  Serial.println("OK");	
}

/******************************************************************************************************************************************************************
  SHT15 Temperature and Humidity sensor
 ******************************************************************************************************************************************************************/
int SHT_shiftIn(int dataPin, int clockPin, int numBits) 
{ 
  int ret = 0; 
 
  for (int i=0; i<numBits; ++i) { 
    digitalWrite(clockPin, HIGH); 
    //delay(10); not needed :) 
    ret = ret*2 + digitalRead(dataPin); 
    digitalWrite(clockPin, LOW); 
  } 
  return(ret); 
} 

// send a command to the SHTx sensor 
void SHT_SendCommand(int command, int dataPin, int clockPin) 
{ 
  int ack; 
 
  // transmission start 
  pinMode(dataPin, OUTPUT); 
  pinMode(clockPin, OUTPUT); 
  digitalWrite(dataPin, HIGH); 
  digitalWrite(clockPin, HIGH); 
  digitalWrite(dataPin, LOW); 
  digitalWrite(clockPin, LOW); 
  digitalWrite(clockPin, HIGH); 
  digitalWrite(dataPin, HIGH); 
  digitalWrite(clockPin, LOW); 
  
  // shift out the command (the 3 MSB are address and must be 000, the last 5 bits are the command) 
  shiftOut(dataPin, clockPin, MSBFIRST, command); 
  
  // verify we get the right ACK 
  digitalWrite(clockPin, HIGH); 
  pinMode(dataPin, INPUT); 
  ack = digitalRead(dataPin); 
  if (ack != LOW) 
  {
    //Serial.println("ACK error 0"); 
  }
  digitalWrite(clockPin, LOW); 
  ack = digitalRead(dataPin); 
  if (ack != HIGH) 
  {
    //Serial.println("ACK error 1"); 
  } 
 
} 

// wait for the SHTx answer 
void SHT_Wait(int dataPin) 
{ 
  int ack; 
 
  pinMode(dataPin, INPUT); 
  for(int i=0; i<100; ++i) { 
    delay(10); 
    ack = digitalRead(dataPin); 
    if (ack == LOW) 
      break; 
  } 
  if (ack == HIGH) 
  {
    //Serial.println("ACK error 2"); 
  }
} 

// get data from the SHTx sensor 
int SHT_GetData16(int dataPin, int clockPin) 
{ 
  int val; 
 
  // get the MSB (most significant bits) 
  pinMode(dataPin, INPUT); 
  pinMode(clockPin, OUTPUT); 
  val = SHT_shiftIn(dataPin, clockPin, 8); 
  val *= 256; // this is equivalent to val << 8; 
  
  // send the required ACK 
  pinMode(dataPin, OUTPUT); 
  digitalWrite(dataPin, HIGH); 
  digitalWrite(dataPin, LOW); 
  digitalWrite(clockPin, HIGH); 
  digitalWrite(clockPin, LOW); 
  
  // get the LSB (less significant bits) 
  pinMode(dataPin, INPUT); 
  val |= SHT_shiftIn(dataPin, clockPin, 8);
  return val; 
} 

// skip CRC data from the SHTx sensor 
void SHT_SkipCRC(int dataPin, int clockPin) { 
  pinMode(dataPin, OUTPUT); 
  pinMode(clockPin, OUTPUT); 
  digitalWrite(dataPin, HIGH); 
  digitalWrite(clockPin, HIGH); 
  digitalWrite(clockPin, LOW); 
} 

// Returns SHT15 current temperature
int SHT_GetTemperature()
{
  static int val;
  static float temperature;          
   
  // read the temperature and convert it to centigrades 
  SHT_SendCommand(SHT15_CMD_TEMPERATURE, SHT_DATA, SHT_CLOCK); 
  
  SHT_Wait(SHT_DATA); 
  val = SHT_GetData16(SHT_DATA, SHT_CLOCK); 
  SHT_SkipCRC(SHT_DATA, SHT_CLOCK); 
  temperature = (float)val * 0.01 - 40; 
    
  return (int)temperature;
  
}

// Get SHT15 current relative humidity
int SHT_GetHumidity()
{
  static int val;
  static float humidity; 
  
  // read the humidity 
  SHT_SendCommand(SHT15_CMD_HUMIDITY, SHT_DATA, SHT_CLOCK); 
  SHT_Wait(SHT_DATA); 
  val = SHT_GetData16(SHT_DATA, SHT_CLOCK); 
  SHT_SkipCRC(SHT_DATA, SHT_CLOCK); 
  humidity = -4.0 + 0.0405 * val + -0.0000028 * val * val;   
  
  return (int)humidity;
}

/******************************************************************************************************************************************************************
  SAA1064 Display driver functions
 ******************************************************************************************************************************************************************/
void clear_display()
{
  Wire.beginTransmission(SAA1064_DRIVER1);	// transmit to device 1
  Wire.send(0x00);            							// sends instruction byte  
  Wire.send(B01000111);             				// sends controldata value byte 
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.endTransmission();
  delay(50);
  Wire.beginTransmission(SAA1064_DRIVER2);	// transmit to device 2
  Wire.send(0x00);            							// sends instruction byte  
  Wire.send(B01000111);             				// sends controldata value byte  
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.send(0x00);
  Wire.endTransmission();
  
  delay(50);

}

void display_num(byte chip_add,byte display,byte numero)
{
  // Begin data
  Wire.beginTransmission(chip_add); // transmit to device 

  // Select display
  Wire.send((byte)display);

  // Send digit value based on font pattern
  Wire.send(digits_font[numero]);

  Wire.endTransmission();     // stop transmitting
}

/******************************************************************************************************************************************************************
  General clock functions
 ******************************************************************************************************************************************************************/
void doDisplayTest()
{
	char i, x;

	Serial.print("Display test...");	

        display_num(SAA1064_DRIVER1,5,8);
        display_num(SAA1064_DRIVER1,6,8);
        display_num(SAA1064_DRIVER1,7,8);
        display_num(SAA1064_DRIVER1,8,8);

        display_num(SAA1064_DRIVER1,3,8);
        display_num(SAA1064_DRIVER1,4,8);
        delay(150);
        
        display_num(SAA1064_DRIVER1,2,8);
        display_num(SAA1064_DRIVER2,1,8);
        delay(150);
        
        display_num(SAA1064_DRIVER1,1,8);
        display_num(SAA1064_DRIVER2,2,8);
        delay(150);

	Serial.println("OK");	

}

// Write a string to memory location
void EepromWriteString(int address, char *string)
{
	int i;

	for (i=0 ; i<strlen(string) ; i++)
	{
		EEPROM.write(address+i, string[i]);
	}
}
/*
// Read a string from memory location
char *EepromWriteString(int address, int size)
{
	int i;

	for (i=0 ; i<strlen(string) ; i++)
	{
		EEPROM.write(address+i, string[i]);
	}
}
*/
// Read and apply config from internal EEPROM
/*
	 NOTE: Internal EEPROM must begin by "WC", otherwise, it will format and set default values

		Memory mapping
		[W][C]
		[Password] (5 chars, default: 12345)

*/

void ReadConfig()
{

		int i;

		Serial.println("Reading internal config...");

		// First two byte must be WC (WallClock) to identify a fully formated eeprom	
		if ( (EEPROM.read(0) == 'W') && (EEPROM.read(1) == 'C') )
		{
			Serial.println("EEPROM format is okey!\n");
		}
		else
		{
			// Seems to be an unknow format so format it now!
			Serial.print("Unknown EEPROM format. Formating 4Kb...");

			// Arduino Mega have 4Kb of EEPROM
			for (i=0 ; i<4096 ; i++)
			{
				EEPROM.write(i, 0);
			}

			// Write default config
			EEPROM.write(0, 'W');
			EEPROM.write(1, 'C');

			//EepromWriteString(2, DEFAULT_PASSWORD);

			Serial.println("OK");
		}
}

// Write current config to internal EEPROM
void WriteConfig()
{
	Serial.print("Writing config to EEPROM...");
	//EEPROM.write(address, value);
	Serial.print("OK");
}

// Set clock time on big digits
void SetClockTime(char hours, char minutes, char seconds)
{	

	// Display hours
	if (hours < 10)
	{
		display_num(SAA1064_DRIVER1,1,0);
		display_num(SAA1064_DRIVER1,2,hours);
	}
	if ( (hours >= 10) && (hours < 20) )
	{
		display_num(SAA1064_DRIVER1,1,1);
		display_num(SAA1064_DRIVER1,2,hours-10);
	}
	if (hours >= 20)
	{
		display_num(SAA1064_DRIVER1,1,2);
		display_num(SAA1064_DRIVER1,2,hours-20);
	}					

	// Display minutes
	if (minutes < 10)
	{
		display_num(SAA1064_DRIVER1,3,0);
		display_num(SAA1064_DRIVER1,4,minutes);
	}
	if ( (minutes >= 10) && (minutes < 20) )
	{
		display_num(SAA1064_DRIVER1,3,1);
		display_num(SAA1064_DRIVER1,4,minutes-10);
	}
	if ( (minutes >= 20) && (minutes < 30) )
	{
		display_num(SAA1064_DRIVER1,3,2);
		display_num(SAA1064_DRIVER1,4,minutes-20);
	}
	if ( (minutes >= 30) && (minutes < 40) )
	{
		display_num(SAA1064_DRIVER1,3,3);
		display_num(SAA1064_DRIVER1,4,minutes-30);
	}
	if ( (minutes >= 40) && (minutes < 50) )
	{
		display_num(SAA1064_DRIVER1,3,4);
		display_num(SAA1064_DRIVER1,4,minutes-40);
	}
	if (minutes >= 50)
	{
		display_num(SAA1064_DRIVER1,3,5);
		display_num(SAA1064_DRIVER1,4,minutes-50);
	}					
		
	// Display seconds
	if (seconds < 10)
	{
		display_num(SAA1064_DRIVER2,1,0);
		display_num(SAA1064_DRIVER2,2,seconds);
	}
	if ( (seconds >= 10) && (seconds < 20) )
	{
		display_num(SAA1064_DRIVER2,1,1);
		display_num(SAA1064_DRIVER2,2,seconds-10);
	}
	if ( (seconds >= 20) && (seconds < 30) )
	{
		display_num(SAA1064_DRIVER2,1,2);
		display_num(SAA1064_DRIVER2,2,seconds-20);
	}
	if ( (seconds >= 30) && (seconds < 40) )
	{
		display_num(SAA1064_DRIVER2,1,3);
		display_num(SAA1064_DRIVER2,2,seconds-30);
	}
	if ( (seconds >= 40) && (seconds < 50) )
	{
		display_num(SAA1064_DRIVER2,1,4);
		display_num(SAA1064_DRIVER2,2,seconds-40);
	}
	if (seconds >= 50)
	{
		display_num(SAA1064_DRIVER2,1,5);
		display_num(SAA1064_DRIVER2,2,seconds-50);
	}				
}

void SetDots(byte state)
{
  digitalWrite(CLOCK_DOT_1, state);
  digitalWrite(CLOCK_DOT_2, state);
  digitalWrite(CLOCK_DOT_3, state);
  digitalWrite(CLOCK_DOT_4, state);  
}

/******************************************************************************************************************************************************************
  Setup
 ******************************************************************************************************************************************************************/
void setup()
{

	char myText[100];
        int i;
        
        wdt_disable();

        // SHT15 Clock PIN
        pinMode(SHT_CLOCK, INPUT);
        
        // Dots pins
        pinMode(CLOCK_DOT_1, OUTPUT);
        pinMode(CLOCK_DOT_2, OUTPUT);
        pinMode(CLOCK_DOT_3, OUTPUT);
        pinMode(CLOCK_DOT_4, OUTPUT);
        
        SetDots(HIGH);

	Serial.begin(9600);	// Enable serial comunication (USB - debug)
        Serial3.begin(9600);	// Enable serial comunication (For XBee)
        Serial2.begin(9600);	// Enable serial comunication (For matrix controller)

	// Print some cool stuff on start :)
	Serial.println(CLOCK_WELCOME);
	Serial.print("Firmware version: "); Serial.print(CLOCK_FIRMWARE_VERSION);
	Serial.print(" release date on: "); Serial.println(CLOCK_FIRMWARE_DATE);

	Serial.println("Starting I2C Bus");
	Wire.begin();  		// Enable I2C protocol

        clear_display();                
	ds1307Init();			// Initialize realtime clock	
	ReadConfig();			// Read and apply saved config
	doDisplayTest();		// Do display test
        clear_display();
        
	// Get time from the RTC
        getDateDs1307(&second, &minute, &hour, &dayOfWeek, &dayOfMonth, &month, &year);
        
        //Init serial parser (Messenger)
        SerialMessage.attach(MsgParser);

	memset(myText, 0, 100);
        sprintf(myText, "Clock started at %02d:%02d:%02d (%02d/%02d/20%02d)", hour, minute, second, dayOfMonth, month, year);
	
	Serial.println(myText);	

	clock_sync = millis() + CLOCK_TIME_UPDATE_RATE; // Force instant update after init

        wdt_enable(WDTO_8S);
}

// Send message over XBee module (Used to set one place for serial port number)
// NOTE: Function with carriage return at the end.
void XBeeSendMsg(char *str)
{
  Serial3.print(str); 
  Serial3.print("\n");
}

/********************************************************************************
  Serial command parser
 ********************************************************************************/
 
 void SkipUnknownCommands()
 {
   
     char tmp[125];
   
    // Clear any pending message (At this point, all messages should be processed, otherwise: Unknown command)
    if (SerialMessage.available())
    {
       while ( SerialMessage.available() ) 
       {
         SerialMessage.copyString(tmp,125);
       }
       
       //Serial.println("KO");
       XBeeSendMsg("KO");
    }   
 }
 
// Cut white char at the begining of a string
void ltrim(char *str)
{
  if (str[0] = ' ')
  {
      int total_len = strlen(str);
      // Shift left to skip begin space
      for (int i=0 ; i<total_len-1 ; i++) { str[i] = str[i+1]; } 
      str[total_len-1] = 0;
  }
}

// Messages parser. Thanks to the Messenger library!
void MsgParser()
{
  
  int val=0;
  char buf[128];
  char tmp[125];
  
  memset(buf, 0, 128);
  memset(tmp, 0, 125);
  // This loop will echo each element of the message separately
  while ( SerialMessage.available() ) 
  {

    if ( SerialMessage.checkString("GET") ) // GET some value
    {
      if ( SerialMessage.checkString("VERSION") ) // VERSION: Return clock firmware version
      { 
        XBeeSendMsg(CLOCK_FIRMWARE_VERSION);
      }
      if ( SerialMessage.checkString("DAY") ) // TIME: Return DAY (Ej: Lunes) - Yes, in spanish! :)
      { 
        sprintf(buf, "%d", dayOfWeek);
        XBeeSendMsg(buf);
      }
      if ( SerialMessage.checkString("TIME") ) // TIME: Return HH:MM:SS
      { 
        sprintf(buf, "%02d:%02d:%02d", hour, minute, second);
        XBeeSendMsg(buf);
      }
      if ( SerialMessage.checkString("DATE") ) // DATE: Return DD/MM/YYYY
      { 
        sprintf(buf, "%02d/%02d/20%02d", dayOfMonth, month, year);
        XBeeSendMsg(buf);
      }
      if ( SerialMessage.checkString("TEMP") ) // TEMP: Return current temperature value
      { 
         val = SHT_GetTemperature();
         sprintf(buf, "%02d", val);
         XBeeSendMsg(buf);
      }
      if ( SerialMessage.checkString("HUMI") ) // HUMI: Return current humidity value
      { 
         val = SHT_GetHumidity();
         sprintf(buf, "%02d", val);
         XBeeSendMsg(buf);
      }
    } 
    if ( SerialMessage.checkString("SET") ) // SET some value
    {
      if ( SerialMessage.checkString("TIME") ) // TIME: Format HOUR MINUTE SECOND DAY MONTH YEAR (All int without left zero, ie: SET TIME 13 4 56 1 4 9 (Return OK when done)
      { 
          int set_hours    = SerialMessage.readInt();
          int set_minutes  = SerialMessage.readInt();
          int set_seconds  = SerialMessage.readInt();
          int set_day      = SerialMessage.readInt();
          int set_month    = SerialMessage.readInt();
          int set_year     = SerialMessage.readInt();
         
          // Save new time value
          setDateDs1307(set_seconds,        // Seconds (0-59)
                        set_minutes,       // Minutes (0-59)
                        set_hours,       // Hours in 24h mode (1-23)
                        0,        // Day of Week (1-7) - 1 = Monday
                        set_day,        // Day of Month (1-28/29/30/31)
                        set_month,       // Month (1-12)
                        set_year);    // Year (0-99)    
                
         //Serial.println("OK");
         XBeeSendMsg("OK");
      }
      
      if ( SerialMessage.checkString("REBOOT") ) // REBOOT: Software reboot (using watchdog)
      { 
        XBeeSendMsg("Rebooting...");
        while (1) {  }
      }      
      
    }
    
    // Send messages to the matrix (The matrix replies on the loop to avoid blocking the clock)    
    if ( SerialMessage.checkString("SM") ) // SM: Set Message (Set current message right now!) ie: SM This is a foo! (Max 125 bytes)
    {
      
      if ( SerialMessage.checkString("EOF") ) // REBOOT: Software reboot (using watchdog)
      { 
        Serial2.print("\r");
      }
      else
      {
      
       memset(buf, 0, 128);
       memset(tmp, 0, 125);      
      
       while ( SerialMessage.available() ) 
       {
         SerialMessage.copyString(tmp,125);
         sprintf(buf, "%s %s", buf, tmp);
       }

       ltrim(buf);       
       //XBeeSendMsg(buf); // DEBUG
       
       // Send data to matrix
       Serial2.print(buf); Serial2.print("\n");
        
      }
    }
  
    // Skip any unknown command pending
    SkipUnknownCommands();    

    Serial.flush();
  }
}

/******************************************************************************************************************************************************************
  Main loop
 ******************************************************************************************************************************************************************/
void loop()
{
        char myText[16];    
        memset(myText, 0, 16);
  
	// The clock need to be updated
	if ((millis() - clock_sync) >= CLOCK_TIME_UPDATE_RATE)
	{      
  
  	    // Get time from the RTC
            getDateDs1307(&second, &minute, &hour, &dayOfWeek, &dayOfMonth, &month, &year);    

            // Display update
            SetClockTime(hour, minute, second);
      
            clock_sync = millis();                                 
  		
  	}	
    
        // Parse serial commands from XBee
        while ( Serial3.available( ) ) SerialMessage.process(Serial3.read( ) );        
        
        // All messages incoming from the matrix goes to Xbee (ClockBase)
        if (Serial2.available( ))
        {            
          
            delay(100);
            //XBeeSendMsg("Incoming...\n");
          
            char tmch=0;
            tmch = Serial2.read();
            
            //XBeeSendMsg("CTL\n");
            
            if (tmch == 2) // Matrix ask for date
            {
               //XBeeSendMsg("Ask date\n");
               getDateDs1307(&second, &minute, &hour, &dayOfWeek, &dayOfMonth, &month, &year);                
               sprintf(myText, "%02d/%02d/20%02d", dayOfMonth, month, year);               

               Serial2.print(myText); Serial2.print("\n");              
               //XBeeSendMsg(myText);
            }
            else
            {
              if (tmch == 3) // Matrix ask for temperature and humidity
              {
                 //XBeeSendMsg("Ask temp\n");
                 int tmp_temp = SHT_GetTemperature();
                 int tmp_humi = SHT_GetHumidity();
                 sprintf(myText, "+%dC (%d%%)", tmp_temp, tmp_humi);
                 Serial2.print(myText); Serial2.print("\n");
                 //XBeeSendMsg(myText);

              }
              else
              {
                  XBeeSendMsg(&tmch);
                  /*
                // Any other messages goes to Xbee (matrix ACK)
                   while ( Serial2.available( ) ) 
                  {
                    tmch = Serial2.read();
                    XBeeSendMsg(&tmch);        
                  }
                  */
              }
            }
            
        }
        
        wdt_reset();
}

