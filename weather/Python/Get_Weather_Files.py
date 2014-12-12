#!/usr/bin/python

import re # regex module
import sys
if sys.version_info.major >= 3:
    import urllib.request as ur
    from html.parser import HTMLParser
else:
    import urllib2 as ur
    from HTMLParser import HTMLParser


def ParseContentTypeForHTMLText(contenttype):
    if contenttype[:9] != 'text/html':
        return (False, None)
    result = re.match('[\S]+charset=([\S]+)', contenttype)
    if result is None:
        return (True, 'utf-8')
    else:
        return (True, result.group(1)) 
        

def GetHTMLTextFromUrl(targeturl, responsefunc=ur.urlopen):
    response = responsefunc(targeturl)
    contenttype = response.getheader('Content-Type')
    istexthtml, encoding = ParseContentTypeForHTMLText(contenttype)
    if not istexthtml:
        raise Exception('Response body is not TEXT/HTML.')
    html = response.read().decode(encoding)
    return html


if __name__ == '__main__':

    print(GetHTMLTextFromUrl('http://www.geos.ed.ac.uk/~weather/jcmb_ws/'))


#class JCMBFileIndex_HTMLParser(HTMLParser):
#    
#    
#
#parser = JCMBFileIndex_HTMLParser()
#
#parser.feed(html)