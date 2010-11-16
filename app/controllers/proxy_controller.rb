class ProxyController < ApplicationController
  
  def proxy
    
    site_url =  request.env["REQUEST_URI"][0..request.env["REQUEST_URI"].index("/proxy")-1] # prefix i.e. "http://localhost:3000"
    if params[:url].blank?
      @url   = URI.unescape(request.env["QUERY_STRING"][4..request.env["QUERY_STRING"].length]) #Full URL from querystring url= "http://..."
    else
      @url = params[:url]
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
      agent.user_agent_alias = 'Mac Safari'
    }
    a.get(@url) do |page|
      @rawdoc =  page.body 
    end    
    
    
    
    # FORMAT HTML CONTENT 
    @doc = Nokogiri::HTML(@rawdoc)
    
    # MANIPULATE HTML CONTENT A AND AREA LINKS TO PASS BACK THROUGH PROXY 
    @doc.xpath('//a|//area').each { |a|

      #regular link found
      if a['href'] != nil
        
        if a['href'].index('http://') == nil and a['href'].index('https://') == nil
          if a['href'] == "/"
            link = @baseurl
          else
            link = @baseurl + a['href']                  
          end
        else
          link = a['href']                
        end

        link.gsub!("http:///", @baseurl) #added to test localhost entries

        #not anchor 
        if a['href'] != nil and a['href'] != "#"

          link = site_url + '/proxy' + '?url=' + URI.escape(link.strip)
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
              link = @baseurl + a['src']
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
              link = @baseurl + a['href']
            end
          else
            link = a['href']
          end

          link.gsub!("http:///", @baseurl) #added to test localhost entries

          link = link.strip
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
            link = @baseurl + a['action']                  
          end
        else
          link = a['action']
        end
    
        link.gsub!("http:///", @baseurl) #added to test localhost entries
    
        if a['action'] != nil and a['action'] != "#"
          
          formaction = link.strip
          link = site_url + '/proxy' + '?url=' + URI.escape(link.strip)
    
          a['action'] = link     

          # Add hidden input text form with url
          lnk_node = Nokogiri::XML::Node.new('input', a)
          lnk_node['type'] = 'hidden'
          lnk_node['name'] = 'url'
          lnk_node['value'] = URI.escape(formaction.strip)
          # a.add_child(lnk_node)
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

