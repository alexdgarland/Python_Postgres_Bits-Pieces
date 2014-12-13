#!/usr/bin/python

import re # regex module
import sys
if sys.version_info.major >= 3:
    import urllib.request as ur
else:
    import urllib2 as ur



def ParseContentTypeForHTMLText(contenttype):
    if contenttype[:9] != 'text/html':
        return (False, None)
    result = re.match('[\S]+charset=([\S]+)', contenttype)
    if result is None:
        return (True, 'utf-8')
    else:
        return (True, result.group(1)) 
        

def GetHTMLTextFromResponse(response):
    contenttype = response.getheader('Content-Type')
    istexthtml, encoding = ParseContentTypeForHTMLText(contenttype)
    if not istexthtml:
        raise Exception('Response content is not TEXT/HTML.')
    html = response.read().decode(encoding)
    return html


class WeatherFile(object):
    def __init__(self, filename, modified_date_string):
        self.filename = filename




if __name__ == '__main__':

    response = ur.urlopen('http://www.geos.ed.ac.uk/~weather/jcmb_ws/')
    html = GetHTMLTextFromResponse(response)
    with open(r'C:\Users\Alexander\Desktop\Index of  ~weather jcmb_ws.html', 'w') as f:
        f.write(html)
    

