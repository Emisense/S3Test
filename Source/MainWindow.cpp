/*
  ==============================================================================

    This file was auto-generated!

    It contains the basic outline for a simple desktop window.

  ==============================================================================
*/

#include "MainWindow.h"
#include "Base64.h"
#include "HMAC_SHA1.h"
#include "AmazonS3.h"

//==============================================================================
MainAppWindow::MainAppWindow()
    : DocumentWindow (JUCEApplication::getInstance()->getApplicationName(),
                      Colours::lightgrey,
                      DocumentWindow::allButtons)
{
    centreWithSize (500, 400);
    setVisible (true);
    
    uint8 testdata[] = { 'a', 'b', 'c' };
    
    String s = Base64::encode (testdata, sizeof(testdata));
    Logger::outputDebugString (s);
    MemoryBlock b = Base64::decode (s);
    Logger::outputDebugString (b.toString());
    
    SHA1 sha;
    sha.update (testdata, sizeof (testdata));
    b = sha.finalize();
    Logger::outputDebugString ("SHA1");
    for (int n=0; n < b.getSize(); n++)
        Logger::outputDebugString (String::toHexString ((uint8)(b[n])));
    
    HMAC_SHA1 hm;
    
    b = hm.encode ("Test", 4, "Key", 3);
    Logger::outputDebugString ("HMAC");
    for (int n=0; n < b.getSize(); n++)
        Logger::outputDebugString (String::toHexString ((uint8)(b[n])));

    String AWSAccessKeyId = "0PN5J17HBGZHT7JJ3X82";
    String AWSSecretAccessKey = "uV3F3YluFJax1cknvbcGwgjvx4QpvB+leU8dUj2o";
    String Expires = "1175139620";
    String HTTPVerb = "GET";
    String ContentMD5 = "";
    String ContentType = "";
    String CanonicalizedAmzHeaders = "";
    String CanonicalizedResource = "/johnsmith/photos/puppy.jpg";
    String string_to_sign = HTTPVerb + "\n" + ContentMD5 + "\n" + ContentType + "\n" + 
    Expires + "\n" + CanonicalizedAmzHeaders + CanonicalizedResource;
 
    HMAC_SHA1 hmac;
    
    b = hmac.encode (string_to_sign, AWSSecretAccessKey);

    Logger::outputDebugString ("HMAC2");
    for (int n=0; n < b.getSize(); n++)
        Logger::outputDebugString (String::toHexString ((uint8)(b[n])));
    
    Logger::outputDebugString (URL::addEscapeChars (Base64::encode (b), true));
        
    AmazonS3 s3 ("AKIAIJR3I2G5CDAGEDHA", "tFNLB44NThsjNlCI/BNs5G1ztbHKtkWm2+cWpkeK");
    S3Object obj ("com.pearsports.mobiledata", "testObj");
    
    S3ObjectInfo objHead = s3.getObjectInfo (obj);
    if (objHead.isValid())
        Logger::outputDebugString (String (objHead.getLength()));

    s3.getObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test")));
    s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test")));
    objHead = s3.getObjectInfo (obj);
    if (objHead.isValid())
        Logger::outputDebugString (String (objHead.getLength()));
    s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test2")));
    objHead = s3.getObjectInfo (obj);
    if (objHead.isValid())
        Logger::outputDebugString (String (objHead.getLength()));
    s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test3")));
    objHead = s3.getObjectInfo (obj);
    if (objHead.isValid())
        Logger::outputDebugString (String (objHead.getLength()));
    
    obj.setId ("testObj666");
    s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test2")));
    objHead = s3.getObjectInfo (obj);
    if (objHead.isValid())
        Logger::outputDebugString (String (objHead.getLength()));    
}

MainAppWindow::~MainAppWindow()
{
}

void MainAppWindow::closeButtonPressed()
{
    JUCEApplication::getInstance()->systemRequestedQuit();
}
