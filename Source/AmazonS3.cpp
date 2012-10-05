/*
  ==============================================================================

    AmazonS3.cpp
    Created: 27 Jun 2012 1:25:29pm
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#include "HMAC_SHA1.h"
#include "Base64.h"
#include "AmazonS3.h"


//==============================================================================
//==============================================================================
const S3ObjectInfo S3ObjectInfo::empty;

//==============================================================================
bool S3ObjectInfo::isSuccess()
{
    return header.fromLastOccurrenceOf ("HTTP", true, false).contains ("200 OK");
}

bool S3ObjectInfo::isValid()
{
    return header.startsWith ("HTTP");
}

//==============================================================================
String S3ObjectInfo::getResult()
{
    String resultLine = header.fromLastOccurrenceOf ("HTTP", true, false)
                              .upToFirstOccurrenceOf ("\n", false, false);
    
    if (! resultLine.startsWith ("HTTP"))
        return String ("Invalid Response");
    
    // Drop the 'HTTP/1.1 xxx '
    return resultLine.substring (13);
}

//==============================================================================
int S3ObjectInfo::getLength()
{
    String lString = header.fromFirstOccurrenceOf ("Content-Length: ", false, true)
                           .upToFirstOccurrenceOf ("\n", false, false);
    
    return lString.getIntValue();
}

//==============================================================================
String S3ObjectInfo::getMD5()
{
    return header.fromFirstOccurrenceOf ("Etag: \"", false, true)
                 .upToFirstOccurrenceOf ("\"", false, false);
}


//==============================================================================
//==============================================================================
bool AmazonS3::getObject (S3Object& object, const File& file)
{
    object.clearFileAndInfo();
    
    S3ObjectInfo objInfo;
    
    // We can't get info for sub-elements
    if (! object.getId().containsChar ('?'))
    {
        if (! updateObjectInfo (object))
            return false;
    
        objInfo = object.getInfo();
    
        if (! objInfo.isSuccess())
            return false;
    }
    
    String url = createURL ("get", object);
    
    String result = runCurl ("--request GET --create-dirs --output '" + 
                             file.getFullPathName() + "' " +
                             "--location '" + url + "'");
    
    if (result.isNotEmpty())
        return false;
    
    // Nothing to match up on sub-element, just try to parse the XML results
    if (object.getId().containsChar ('?'))
    {
        object.setInfo (S3ObjectInfo ("HTTP 200 OK"));
        return true;
    }
    
    // We can't verify the length and md5 of directory requests, again, just
    // verify the XML
    if (! object.getId().length())
        return true;
    
    if (file.getSize() != objInfo.getLength())
        return false;
    
    // Data file request, compare md5
    MD5 md5 (file);
    
    if (md5.toHexString().compareIgnoreCase (objInfo.getMD5()))
        return false;
    
    object.setFile (file);
    return true;
}

bool AmazonS3::putObject (S3Object& object, const File& file, bool makePublic)
{
    object.clearFileAndInfo();
    
    if (! file.exists())
        return false;
    
    String url;
    String header;
    
    if (makePublic)
    {
        header = "--header 'x-amz-acl:public-read' ";
        url = createURL ("put", object, "x-amz-acl:public-read\n");
    }
    else
    {
        header = "";
        url = createURL ("put", object);
    }
    
    object.setInfo (S3ObjectInfo (runCurl (header + "--request PUT --dump-header - --upload-file '" +
                                  file.getFullPathName() + "' " +
                                  "--location '" + url + "'")));
    
    if (! object.isSuccess())
        return false;
    
    MD5 md5 (file);
    
    if (md5.toHexString().compareIgnoreCase (object.getInfo().getMD5()))
        return false;

    object.setFile (file);
    return true;
}

//==============================================================================
bool AmazonS3::getDirectory (const String& bucket, StringArray& list)
{
    list.clear();
    
    File temp = File::createTempFile (".xml");
    
    S3Object object (bucket, "");
    
    if (! getObject (object, temp))
    {
        temp.deleteFile();
        return false;
    }
    
    XmlElement* xml = XmlDocument::parse (temp);
    temp.deleteFile();
    
    if (xml != nullptr)
    {
        forEachXmlChildElementWithTagName(*xml, c, "Contents")
        {
            XmlElement *key = c->getChildByName("Key");
            if (key)
                list.add (key->getAllSubText());
        }
        
        delete xml;
        return true;
    }
    
    return false;
}

//==============================================================================
bool AmazonS3::updateObjectInfo (S3Object& object)
{
    object.clearFileAndInfo();
    
    object.setInfo (S3ObjectInfo (runCurl ("--head '" + createURL ("head", object) + "'")));

    return object.isSuccess();
}

//==============================================================================
String AmazonS3::createURL (const String& verb, const S3Object& object, const String& amzHeader)
{
    // Create a signiture
    String expires ((Time::getCurrentTime().toMilliseconds() / 1000) + 300);
    String canonicalizedResource = "/" + object.getBucket() + "/" + object.getId();

    String signString = verb.toUpperCase() + "\n\n\n" + 
                        expires + "\n" +
                        amzHeader +
                        canonicalizedResource;
    
    String signature = URL::addEscapeChars (Base64::encode (HMAC_SHA1::encode (signString, secret)), true);

    // Build up the URL
    String url;
    
    if (! object.getId().containsChar ('?'))
        url = "https://" + object.getBucket() + ".s3.amazonaws.com/" + object.getId() +
                 "?AWSAccessKeyId=" + URL::addEscapeChars (credentials, true) +
                 "&" + "Expires=" + expires + "&Signature=" + signature;
    else
        url = "https://" + object.getBucket() + ".s3.amazonaws.com/" + object.getId() +
        "&AWSAccessKeyId=" + URL::addEscapeChars (credentials, true) +
        "&" + "Expires=" + expires + "&Signature=" + signature;
        
    return url;
}

//==============================================================================
String AmazonS3::runCurl (const String& cmdLine)
{
    String result;
    
    String process;
    
#if JUCE_WINDOWS
    process = ".\curl.exe ";
#else
    process = "curl ";
#endif
    
    // Add common options before, redirect after
    process += "-q -g -S --remote-time --retry 3 -s ";
    process += cmdLine;
    process += " 2>&1";
    
#if JUCE_MAC
    FILE* pipe = popen(process.toUTF8(), "r");
    if (pipe)
    {
        char buffer[128];
        while (!feof (pipe))
        {
            if (fgets (buffer, 128, pipe) != NULL)
                result += buffer;
        }
        pclose (pipe);
    }
#else
    ChildProcess childProcess;
    childProcess.start (process);
    result = childProcess.readAllProcessOutput();
#endif
    return result;
}
