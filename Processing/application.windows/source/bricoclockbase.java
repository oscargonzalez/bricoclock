import processing.core.*; 
import processing.xml.*; 

import processing.net.*; 
import processing.serial.*; 

import java.applet.*; 
import java.awt.Dimension; 
import java.awt.Frame; 
import java.awt.event.MouseEvent; 
import java.awt.event.KeyEvent; 
import java.awt.event.FocusEvent; 
import java.awt.Image; 
import java.io.*; 
import java.net.*; 
import java.text.*; 
import java.util.*; 
import java.util.zip.*; 
import java.util.regex.*; 

public class bricoclockbase extends PApplet {

/*
  WallClock Net app client
  Code: Oscar Gonzalez - March 2010
  www.BricoGeek.com
*/




PrintWriter debug;

XMLElement xml;
PFont myFont;
Serial myPort;  // Create object from Serial class
Client c;
String data;

// Global variables for general config
String config_comname;
String config_syncrate;
String config_timesync;
String config_feedurl;
String last_sync = "-";

String debug_text = "";

int SYNC_RATE  = 30; // Sync every 10 minutes
int lastFeedSync=0;

// Wait until matrix reply
public boolean WaitForMatrix()
{
  
  int start = millis();
  
  println("Wait matrix...");
  // Wait for something to read
  while ( (myPort.available() == 0) && ((millis()-start) < 3000) )  { }
  
  if (myPort.available() == 0) { println("Timeout: Clock is busy!"); ShowScreen("Clock is busy!"); return false; } 
  
  println("Matrix get...");
  // Read serial (whatever)
  while (myPort.available() > 0) {
    int inByte = myPort.read();
    println(PApplet.parseChar(inByte));
  }
  
  return true;
}

public void GetFeed()
{
  // Download RSS feed of news stories
  println("Download Feed from "+config_feedurl+"...");
  // Download RSS feed of news stories from yahoo.com
  //String url = "http://blog.makezine.com/index.xml";
  String url = config_feedurl;
  XMLElement rss = new XMLElement(this, url);
  // Get all  elements
  XMLElement[] links = rss.getChildren("channel/item/title");
  
  int availableBytes=1024; // total free bytes in buffer
  
  int totalBytes=0;
  int total_msg=0;
  
  last_sync = day() +"/"+month()+"/"+year()+" - "+hour()+":"+minute()+":"+second();
  
  // Count total messages to send
  for (int i = 0; i < links.length; i++) {
    String title = links[i].getContent();
    // Comprobamos si hay espacio suficiente para \u00e9ste noticia
    if (title.length() < availableBytes) 
    {
       availableBytes -= title.length(); 
       total_msg++; 
    }
  }
  
  println("Total messages: "+total_msg);
  myPort.write("SM 1\r"); 
  ShowScreen("Feed OK. Waiting for clock...");
  delay(300);
  if (!WaitForMatrix()) { return; }
  println("Sending messages...");
  
  availableBytes=1024; // Reset available bytes
  
  // Now parse and send!
  for (int i = 0; i < links.length; i++) {
    String title = links[i].getContent();
    
    // Comprobamos si hay espacio suficiente para \u00e9ste noticia
    if (title.length() < availableBytes) {
      print(title.length()+" "); println(title);
      //myPort.write(title); myPort.write('\n');
      OutputText("SM "+title);
      WaitForMatrix();
      
      totalBytes += title.length() + 1; // One myte more for \r
      availableBytes -= title.length() + 1;
      
    }
  }
  myPort.write("SM EOF\r"); // Control byte (end)
  println("Total bytes: "+totalBytes);  
  
  // Get messages
  while( myPort.available() > 0) 
  {
    print(myPort.read());         // read it and store it in val
  }  
  
  
}

public void GetConfig()
{

  println("Get config...");
  debug.println("Get config");
  debug.flush();  
  XMLElement cxml;
    
  cxml = new XMLElement(this, "config.xml");
  int numSites = cxml.getChildCount();
  for (int i = 0; i < numSites; i++) {
    XMLElement kid = cxml.getChild(i);
    //int id = kid.getIntAttribute("id"); 
    config_comname    = kid.getStringAttribute("port");       // COM port for Xbee
    config_syncrate   = kid.getStringAttribute("sync_rate");  // Sync rate of the feed in seconds
    config_timesync   = kid.getStringAttribute("time_sync");  // Date/Time sync rate in seconds (recomended 21600 - every 6 hours)
    config_feedurl    = kid.getStringAttribute("feed");       // Feed URL
  }
  
  println(" Port: " + config_comname);    
  println(" Sync rate: " + config_syncrate + " seconds");    
  println(" Feed URL: " + config_feedurl);    
  
  debug.println(" Port: " + config_comname);    
  debug.println(" Sync rate: " + config_syncrate + " seconds");    
  debug.println(" Feed URL: " + config_feedurl);    
  debug.flush();
  
}

// Set time and date to clock
public void SyncTime()
{ 
  println("Time sync");
  myPort.write("SET TIME "+(hour())+" "+minute()+" "+second()+" "+day()+" "+month()+" "+(year()-2000)+"\r");
}

public void OutputText(String strText)
{
  int text_len = strText.length();
  
  for (int i=0 ; i<text_len ; i++)
  {
      switch (strText.charAt(i))
      {
        case '\u00e1': { myPort.write("a"); }; break;  
        case '\u00e9': { myPort.write("e"); }; break;  
        case '\u00ed': { myPort.write("i"); }; break;  
        case '\u00f3': { myPort.write("o"); }; break;  
        case '\u00fa': { myPort.write("u"); }; break;  
        
        case '\u00c1': { myPort.write("A"); }; break;  
        case '\u00c9': { myPort.write("E"); }; break;  
        case '\u00cd': { myPort.write("I"); }; break;  
        case '\u00d3': { myPort.write("O"); }; break;  
        case '\u00da': { myPort.write("U"); }; break;  
        
        case '\u00f1': { myPort.write("n"); }; break;  
        case '\u00d1': { myPort.write("N"); }; break;  
        
        case '\u00e2': { myPort.write("a"); }; break;  
        case '\u00ea': { myPort.write("e"); }; break;  
        case '\u00ee': { myPort.write("i"); }; break;  
        case '\u00f4': { myPort.write("o"); }; break;  
        case '\u00fb': { myPort.write("u"); }; break;  
        
        case '\u00e4': { myPort.write("a"); }; break;  
        case '\u00eb': { myPort.write("e"); }; break;  
        case '\u00ef': { myPort.write("i"); }; break;  
        case '\u00f6': { myPort.write("o"); }; break;  
        case '\u00fc': { myPort.write("u"); }; break;          
        
        case '\u00bf': { myPort.write("?"); }; break;  
        case '\u00a1': { myPort.write("!"); }; break;  
        
        case '\u00e7': { myPort.write("c"); }; break;  
        
        default: { myPort.write(strText.charAt(i)); }
      }
  }
  myPort.write("\r");
}

public void keyReleased() {
  if (PApplet.parseInt(key) == 10) // ENTER
  {
   GetFeed();    
   //SyncTime();
  }
}

public void ShowScreen(String DebugText)
{
  fill(200);
  
  myFont = createFont("verdana", 12);
  textFont(myFont);
  
  fill(0, 0, 0);
  rect(0, 0, 300, 200);
  
  fill(255, 255, 255);
  
  text("BricoClock Base - Oscar Gonzalez 2009-2010", 5, 15);  
  text("www.BricoGeek.com", 80, 30);  
  
  text("COM Port:", 5, 50);  
  text(config_comname, 80, 50);  
  
  text("Feed rate:", 5, 64);  
  text(config_syncrate+" seconds", 80, 64);  
  
  text("Feed URL:", 5, 78);  
  text(config_feedurl, 80, 78);  
  
  text("Last sync:", 5, 92);  
  text(last_sync, 80, 92);  
  
  text(DebugText, 5, 110);  

  fill(255, 255, 0);
  rect(100, 120, 100, 20);
  fill(0, 0, 0);
  color(0, 255, 0);
  text("Update now!", 110, 135);  
}

public void setup() {
  
  debug = createWriter("debug.log");  
  debug.println("*** Start ClockBase ***");
  debug.flush();
  
  GetConfig();
  
  //String portName = Serial.list()[2];
  myPort = new Serial(this, config_comname, 9600); // 9600 8 N 1
  
  println(config_comname);
  
  //c = new Client(this, "news.google.com", 80); // Connect to server on port 80
  //c.write("GET /news?pz=1&hdlOnly=1&cf=all&ned=es&hl=es&topic=t&output=rss HTTP/1.1\n"); // Use the HTTP "GET" command to ask for a Web page
  //c.write("Host: news.google.com\n\n"); // Be polite and say who we are
  
  //createInput("news.google.com/news?pz=1&hdlOnly=1&cf=all&ned=es&hl=es&topic=t&output=rss");
  
  frameRate(1);
  size(300, 150);
  background(50);

  ShowScreen("");
  
  // Download Feed
  //GetFeed();
  
  //SyncTime();
  
}

public void mousePressed()
{
  if (overRect(100, 120, 100, 20))
  {
      ShowScreen("Updating feed...");
     GetFeed();   
  }
}

public boolean overRect(int x, int y, int width, int height) 
{
  if (mouseX >= x && mouseX <= x+width && 
      mouseY >= y && mouseY <= y+height) {
    return true;
  } else {
    return false;
  }
}

int sync_counter=0;
int time_sync_counter=0;
public void draw() {
  
  String d = "sync: "+sync_counter;
  ShowScreen(d);
  
  // Feed sync
  if (sync_counter > PApplet.parseInt(config_syncrate)) 
  { 
    GetFeed(); 
    sync_counter=0; 
  }
  
  // Date/Time sync
  if (time_sync_counter > PApplet.parseInt(config_timesync)) 
  { 
    SyncTime();
    time_sync_counter=0;
  }
  
  sync_counter++;
  time_sync_counter++;
  
}

  static public void main(String args[]) {
    PApplet.main(new String[] { "--bgcolor=#ECE9D8", "bricoclockbase" });
  }
}
