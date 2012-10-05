/*
  ==============================================================================

    This file was auto-generated!

    It contains the basic outline for a simple desktop window.

  ==============================================================================
*/

#include "MainWindow.h"
#include "Base64.h"
#include "SHA1.h"
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
    
    b = HMAC_SHA1::encode ("Test", 4, "Key", 3);
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
 
    b = HMAC_SHA1::encode (string_to_sign, AWSSecretAccessKey);

    Logger::outputDebugString ("HMAC2");
    for (int n=0; n < b.getSize(); n++)
        Logger::outputDebugString (String::toHexString ((uint8)(b[n])));
    
    // Should be "rucSbH0yNEcP9oM2XNlouVI3BH4%3d"
    Logger::outputDebugString (URL::addEscapeChars (Base64::encode (b), true));
        
    AmazonS3 s3 ("AKIAIJR3I2G5CDAGEDHA", "tFNLB44NThsjNlCI/BNs5G1ztbHKtkWm2+cWpkeK");
    S3Object obj ("com.pearsports.mobiledata", "testObj");
    
    if (s3.updateObjectInfo (obj))
        if (obj.isSuccess())
            Logger::outputDebugString (String (obj.getInfo().getLength()));
    Logger::outputDebugString (obj.getResult());

    if (s3.getObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test"))))
    {
        if (obj.isSuccess())
            Logger::outputDebugString ("Get OK");
    }
    Logger::outputDebugString (obj.getResult());
    Logger::outputDebugString (obj.getInfo().getRawHeader());

    if (s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test"))))
    {
        if (obj.isSuccess())
            Logger::outputDebugString ("Put OK");
    }
    Logger::outputDebugString (obj.getResult());
    Logger::outputDebugString (obj.getInfo().getRawHeader());

    obj.setId ("testObj666");
    if (s3.putObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test2")), true))
    {
        if (obj.isSuccess())
            Logger::outputDebugString ("Put 666 OK");
    }
    Logger::outputDebugString (obj.getResult());
    Logger::outputDebugString (obj.getInfo().getRawHeader());
    
    obj.setId ("testObj666?acl");
    if (s3.getObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test-acl"))))
        if (obj.isSuccess())
            Logger::outputDebugString ("Get ACL OK");
    Logger::outputDebugString (obj.getInfo().getRawHeader());
    
    obj.setId ("");
    if (s3.getObject (obj, File (CharPointer_UTF8 ("~/Src/aws/test-ls"))))
        if (obj.isSuccess())
            Logger::outputDebugString ("Get LS OK");
    Logger::outputDebugString (obj.getInfo().getRawHeader());
    
    StringArray list;
    if (s3.getDirectory ("com.pearsports.mobiledata", list))
    {
        for (int n=0; n < list.size(); n++)
            Logger::outputDebugString (list[n]);
    }
}

MainAppWindow::~MainAppWindow()
{
}

void MainAppWindow::closeButtonPressed()
{
    JUCEApplication::getInstance()->systemRequestedQuit();
}
