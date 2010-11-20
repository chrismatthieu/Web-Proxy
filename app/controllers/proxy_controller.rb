class ProxyController < ApplicationController
  
  def proxy
    
    # DIDNT WORK IN PROD
    # site_url =  request.env["REQUEST_URI"][0..request.env["REQUEST_URI"].index("/proxy")-1] # prefix i.e. "http://localhost:3000"
    
    if request.env["REQUEST_URI"].index("http://localhost")
      site_url = "http://localhost:3000"
    else
      site_url = "http://webproxy.heroku.com"
    end
    
    if params[:lnk]
      @url = params[:lnk]
    else
      @url   = URI.unescape(request.env["QUERY_STRING"][4..request.env["QUERY_STRING"].length])  #Full URL from querystring url= "http://..."
    end
    method = request.env["REQUEST_METHOD"]
    data   = request.env["RAW_POST_DATA"] #if empty add the actual querystring to data
    port   = 80               
                        
    # Prepend http/https protocol if not present
    if @url.index('http://') == nil and @url.index('https://') == nil
      @url = 'http://' + @url
    end
    
    # @baseurl i.e. http://example.com/
    # @xurl i.e. http://example.com/subsirectory/
    @uri = URI.parse(@url)
    @baseurl = @uri.scheme + '://' + @uri.host
    if @url.length == @baseurl.length
      @xurl = @url
    else
      iOffset = @url.rindex('/')
      @xurl = @url[0..iOffset]
    end
    if @xurl[-1,1] != "/"
      @xurl=@xurl + "/"
    end
    # if @baseurl[-1,1] != "/"
    #   @baseurl=@baseurl + "/"
    # end
    
    # determines querystring i.e. http://example.com/subsirectory?data=this_stuff
    iOffset = @url.rindex('?')
    if iOffset != nil
      @geturl = @url[0..iOffset-1] #url including page i.e. http://example.com/subsirectory/test.html less the querystring
      @query = @url[iOffset+1..@url.length] #querystring
      path = "/" + @url[@xurl.length..iOffset-1] rescue "/" #only the page i.e. /test.html
    else
      @geturl = @url
      @query = "" #querystring
      path = "/" + @url[@xurl.length..@url.length]  rescue "/"         
    end
    
    host = @uri.host #only domain

    
    a = Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari' #TODO pass user's browser type
      # User Agent aliases
        # AGENT_ALIASES = {
        #   'Windows IE 6' => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)',
        #   'Windows IE 7' => 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322; .NET CLR 2.0.50727)',
        #   'Windows Mozilla' => 'Mozilla/5.0 (Windows; U; Windows NT 5.0; en-US; rv:1.4b) Gecko/20030516 Mozilla Firebird/0.6',
        #   'Mac Safari' => 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; de-at) AppleWebKit/531.21.8 (KHTML, like Gecko) Version/4.0.4 Safari/531.21.10',
        #   'Mac FireFox' => 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2) Gecko/20100115 Firefox/3.6',
        #   'Mac Mozilla' => 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.4a) Gecko/20030401',
        #   'Linux Mozilla' => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.4) Gecko/20030624',
        #   'Linux Firefox' => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.1) Gecko/20100122 firefox/3.6.1',
        #   'Linux Konqueror' => 'Mozilla/5.0 (compatible; Konqueror/3; Linux)',
        #   'iPhone' => 'Mozilla/5.0 (iPhone; U; CPU like Mac OS X; en) AppleWebKit/420+ (KHTML, like Gecko) Version/3.0 Mobile/1C28 Safari/419.3',
        #   'Mechanize' => "WWW-Mechanize/#{VERSION} (http://rubyforge.org/projects/mechanize/)"
        # }
    }
    
    # Page request from form
    if params[:verb]
      
      if params[:verb] == 'get' 
        # puts params
        # puts @url
        
        #Add a question mark to the end of the base url if one does not exist
        if @url.index('?') == nil
          @url << '?'
        end

        #Build params query string
        params.each do |k, v|
          if k != 'lnk' and k != 'verb'
            @url << "&#{k}=#{v}"
          end
         end
        
        a.get(@url) do |page|
          @rawdoc =  page.body 
        end
        
        
      else #POST
        
        # page = browser.post('http://www.mysite.com/login', {
        #   "email" => "myemail%40gmail.com",
        #   "password" => "something",
        #   "remember" => "1",
        #   "loginSubmit" => "Login",
        #   "url" => ""
        # })
        
          #THERE HAS GOT TO BE A BETTER WAY TO FORMAT PARAMS FOR MECHANIZE POST
          paramsstring = ""
          s = params.to_query
          paramsarray = s.split('&')
          paramsarray.each do |element|
            elementarray = element.split('=')
              if  !elementarray[1].nil?
                paramsstring << '"' + elementarray[0] + '" => "' +  URI.unescape(elementarray[1]) + '", '
              end
          end
                    
          # TEST = http://www.cs.unc.edu/~jbs/resources/perl/perl-cgi/programs/form1-POST.html
          page = a.post(@url, eval("{" + paramsstring.chop.chop + "}")) 
          @rawdoc = page.body

      end
          
    else
      begin
        a.get(@url) do |page| 
          @rawdoc =  page.body 
        end    
      rescue
        @rawdoc = "Page not found"
      end
    end
    
    
    # FORMAT HTML CONTENT 
    @doc = Nokogiri::HTML(@rawdoc)
    
    # MANIPULATE HTML CONTENT A AND AREA LINKS TO PASS BACK THROUGH PROXY 
    @doc.xpath('//a|//area').each { |a|

      #regular link found
      if a['href'] != nil and a['href'][0..0] != "#" # dont process for anchor tags
        
        if a['href'].index('http://') == nil and a['href'].index('https://') == nil
          if a['href'] == "/"
            link = @baseurl
          else
            if @baseurl[@baseurl.length..@baseurl.length] == '/' or a['href'][0..0] == "/"
              link = @baseurl + a['href']
            else
              link = @baseurl + '/' + a['href']
            end
          end
        else
          link = a['href']                
        end

        link.gsub!("http:///", @baseurl) #added to test localhost entries

        #not anchor 
        if a['href'] != nil and a['href'] != "#"

          link = site_url + '/proxy' + '?lnk=' + URI.escape(link.strip)
          a['href'] = link

        end
      end
    }
    
    # MANIPULATE HTML CONTENT IMAGES, SCRIPTS, AND IFRAMES TO USE ACTUAL LINKS INCLUDING RELATIVE LINKS
    @doc.xpath('//img|//script|//iframe').each { |a|

        if a['src'] != nil

          if a['src'].index('http://') == nil and a['src'].index('https://') == nil
            if a['src'] == "/"
              link = @baseurl
            else
              if @baseurl[@baseurl.length..@baseurl.length] == '/' or a['src'][0..0] == "/"
                link = @baseurl + a['src']
              else
                link = @baseurl + '/' + a['src']
              end
            end
          else
            link = a['src']
          end

          link.gsub!("http:///", @baseurl) #added to test localhost entries

          if a['src'] != nil and a['src'] != "#"

            link = link.strip
            a['src'] = link

          end
        end
    }
    
    # MANIPULATE HTML CONTENT IMAGES TO USE ACTUAL LINKS INCLUDING RELATIVE LINKS
    @doc.xpath('//link').each { |a|

        if a['href'] != nil

          if a['href'].index('http://') == nil and a['href'].index('https://') == nil
            if a['href'] == "/"
              link = @baseurl
            else
              if @baseurl[@baseurl.length..@baseurl.length] == '/' or a['href'][0..0] == "/"
                link = @baseurl + a['href']
              else
                link = @baseurl + '/' + a['href']
              end
            end
          else
            link = a['href']
          end

          link.gsub!("http:///", @baseurl) #added to test localhost entries

          link = link.strip
          # link = site_url + '/proxy' + '?lnk=' + URI.escape(link.strip)
          a['href'] = link
          
        end
    } 
    
      # MANIPULATE HTML CONTENT IMAGES TO USE ACTUAL LINKS INCLUDING RELATIVE LINKS
      @doc.xpath('//form').each { |a|
    
      if a['action'] != nil
        
        if a['action'].index('http://') == nil and a['action'].index('https://') == nil
          if a['action'] == "/"
            link = @baseurl
          else
            if @baseurl[@baseurl.length..@baseurl.length] == '/' or a['action'][0..0] == "/"
              link = @baseurl + a['action']
            else
              link = @baseurl + '/' + a['action']
            end
          end
        else
          link = a['action']
        end
        
        method = a['method']
        if !method
          method = "get"
        end
        method.downcase
    
        link.gsub!("http:///", @baseurl) #added to test localhost entries
    
        if a['action'] != nil and a['action'] != "#"
          
          formaction = link.strip
          link = site_url + '/proxy' + '?url=' + URI.escape(link.strip)
    
          a['action'] = link     

          # Add hidden input text form with url
          lnk_node = Nokogiri::XML::Node.new('input', a)
          lnk_node['type'] = 'hidden'
          lnk_node['name'] = 'lnk'
          lnk_node['value'] = URI.escape(formaction.strip)
          a.add_child(lnk_node)

          # Add hidden input text form with verb
          lnk_node = Nokogiri::XML::Node.new('input', a)
          lnk_node['type'] = 'hidden'
          lnk_node['name'] = 'verb'
          lnk_node['value'] = method
          a.add_child(lnk_node)

        end
      end
    }
    
    ##FINAL MISC CLEANUP
    @finaldoc = @doc.to_s 
    
    # #Check for any links that may be hiding in javascripts
    # @finaldoc.gsub("href='/", "href='" + site_url + "/proxy?url=" + @baseurl)
    # 
    # #prepend baseurl on src tags in javascript
    # @finaldoc.gsub('src="/', 'src="' + @baseurl + '/' ) 
    # 
    # #Why does Amazon care about Firefox browsers?
    # @finaldoc.gsub('Firefox', 'FirefoxWTF' ) 

    # FIX JAVASCRIPT RELEATIVE URLS
    # @finaldoc.gsub("script('/", "script('" + @baseurl)

    # #Hack to remove double wacks in URL ie http://sunsounds.org//audio//programs
    # @finaldoc.gsub!("://", "/::")
    # @finaldoc.gsub!("//", "/")
    # @finaldoc.gsub!("/::", "://")         
    
    #Add baseURL to code within embedded styles
    @finaldoc.gsub("url(/", "url(" + @baseurl)  
    
    #Remove frame breaking javascript
    @finaldoc.gsub(".location.replace", "") 
    

    render :layout => false

  end

end

