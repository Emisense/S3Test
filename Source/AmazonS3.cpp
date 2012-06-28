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
bool S3ObjectInfo::isValid()
{
    return header.fromLastOccurrenceOf ("HTTP", true, false).contains ("200 OK");
}

//==============================================================================
String S3ObjectInfo::resultCode()
{
    String resultLine = header.fromLastOccurrenceOf ("HTTP", true, false)
                              .upToFirstOccurrenceOf ("\n", false, false);
    
    if (! resultLine.startsWith ("HTTP"))
        return String ("Invalid");
    
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
bool AmazonS3::getObject (const S3Object& object, const File& file)
{
    S3ObjectInfo objInfo = getObjectInfo (object);
    if (! objInfo.isValid())
        return false;
    
    String url = createURL ("get", object);
    
    String result = runCurl ("--request GET --create-dirs --output '" + 
                             file.getFullPathName() + "' " +
                             "--location '" + url + "'");
    
    if (result.isNotEmpty())
        return false;
    
    if (file.getSize() != objInfo.getLength())
        return false;
    
    MD5 md5 (file);
    
    if (md5.toHexString().compareIgnoreCase (objInfo.getMD5()))
        return false;
    
    return true;
}

bool AmazonS3::putObject (const S3Object& object, const File& file)
{
    if (! file.exists())
        return false;
    
    String url = createURL ("put", object);
    
    S3ObjectInfo objInfo (runCurl ("--request PUT --dump-header - --upload-file '" +
                                   file.getFullPathName() + "' " +
                                   "--location '" + url + "'"));
    
    if (! objInfo.isValid())
        return false;
    
    MD5 md5 (file);
    
    if (md5.toHexString().compareIgnoreCase (objInfo.getMD5()))
        return false;

    return true;
}

//==============================================================================
S3ObjectInfo AmazonS3::getObjectInfo (const S3Object& object)
{
    return S3ObjectInfo (runCurl ("--head '" + createURL ("head", object) + "'"));
}

//==============================================================================
String AmazonS3::createURL (const String& verb, const S3Object& object)
{
    // Create a signiture
    String expires ((Time::getCurrentTime().toMilliseconds() / 1000) + 300);
    String canonicalizedResource = "/" + object.getBucket() + "/" + object.getId();

    String signString = verb.toUpperCase() + "\n\n\n" + 
                        expires + "\n" + 
                        canonicalizedResource;
    
    String signature = URL::addEscapeChars (Base64::encode (HMAC_SHA1().encode (signString, secret)), true);

    // Build up the URL
    String url = "https://" + object.getBucket() + ".s3.amazonaws.com/" + object.getId() +
                 "?AWSAccessKeyId=" + URL::addEscapeChars(credentials, true) +
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
