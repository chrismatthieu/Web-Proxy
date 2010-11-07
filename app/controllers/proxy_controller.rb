class URI::HTTP
    def +(new_loc)
        URI.parse(
            case new_loc
              when /^[\/]/    then "http://#{host}:#{port}#{new_loc}"
              when /^.{3,6}:/ then new_loc
              else                 "http://#{host}:#{port}#{path.sub(/\/?[^\/]*$/,'/' + new_loc)}"
              end
            )
        end
    end
    
class Net::HTTPResponse
    def after_redirection_from(uri)
        self
    end
end

class Net::HTTPRedirection
    def after_redirection_from(uri)
        Net::HTTP.get_response(uri + self['location']).after_redirection_from(uri) rescue ""
    end
end

class String
    def prefixes(delimiter='/')
        segments = split(delimiter)
        (1..segments.length).collect { |i| segments[0..-i].join(delimiter) }
        end
    def suffixes(delimiter='/')
        segments = split(delimiter)
        (1..segments.length).collect { |i| segments[(i-1)..-1].join(delimiter) }
        end
    end

class A_cookie_jar
    def initialize
        @jar = {}
        end
    def parse_cookie_from(uri,s)
        return unless s.is_a? String and s.length > 2
        cookies = s.gsub(/, ([^\d])/,';;\1').split(';;')
        cookies.each { |cookie|
            name_value,*options = cookie.split(';')
            name,value = name_value.split('=')
            acceptable_protocols,domain,path,expires = ['http','https'],uri.host,uri.path,nil
            options.each { |option| case option
                when /expires=.+?, (..-...-..(..)? ..:..:.. GMT)/
                    expires = DateTime.parse($1,:guess_year)
                when /path=(.*)/                     
                    path = $1
                when /domain=(.*)/                      
                    domain = $1
                when /secure/                                
                    acceptable_protocols = ['https']
                end}
            ((@jar[domain] ||= {})[path] ||= []) << [name,value,expires, acceptable_protocols]
            }
        end
    def cookies_for(uri)
        result = {}
        uri.host.suffixes('.').each { |domain|
            uri.path.prefixes.each { |path|
                @jar[domain][path].each { |name,value,expires,acceptable_protocols|
                    (result[name] ||= []) << value if DateTime.now < expires and acceptable_protocols.include? uri.scheme
                    } if @jar[domain].has_key? path
                path += '/'    
                } if @jar.has_key? domain
            }
            
          def result.to_s
          keys.collect { |name|
              self[name].collect { |value| "#{name}=#{value}" }
              }.flatten.join(';')
          end
        result
        end
    end


class ProxyController < ApplicationController
  
  def cookie_jar
    session[:cookie_jar] ||= A_cookie_jar.new
  end
  
  def fetch(method,uri,data)
    headers = {'Cookie' => cookie_jar.cookies_for(uri).to_s } 
    args    = (method == 'POST' || method == 'PUT') ? [ data, headers ] : [ headers ]
    response = Net::HTTP.start(uri.host,uri.port) { |x| x.send(method.downcase,[uri.path,uri.query].join('?'), args) } 
    cookie_jar.parse_cookie_from(uri,response['set-cookie']) 
    response = fetch('GET',uri + response['location'],data) if response.is_a? Net::HTTPRedirection
    response
  end

  def proxy
    
    site_url =  request.env["REQUEST_URI"][0..request.env["REQUEST_URI"].index("/proxy")-1] #"http://localhost:3000"
    @url   = URI.unescape(request.env["QUERY_STRING"][4..request.env["QUERY_STRING"].length]) #Full URL (url=http://...)
    method = request.env["REQUEST_METHOD"]
    data   = request.env["RAW_POST_DATA"] #if empty add the actual querystring to data
    port   = 80        
    
    # if method.nil?
    #   method = "GET"
    # end
        
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
    if @baseurl[-1,1] != "/"
      @baseurl=@baseurl + "/"
    end
    
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

    
    
    # FETCH PAGE
    # # Works - but doesnt support cookies
    # response = Net::HTTP.start(host,port) { |x| 
    #     x.send(method.downcase,path,data) 
    #     }    
    # @rawdoc = response.after_redirection_from(@uri).body rescue ""

        
    ## Cookie Support - doesn't work    
    # response = fetch(method, URI.parse(@url), data)           
    # @rawdoc = response.body


    ## Cookie Support - doesn't work    
    # headers = {'Cookie' => cookie_jar.cookies_for(@uri).to_s } 
    # args    = (method == 'POST' || method == 'PUT') ? [ data, headers ] : [ headers ]
    # response = Net::HTTP.start(@uri.host,@uri.port) { |x| x.send(method.downcase, [path, @query].join('?'), args) } 
    # cookie_jar.parse_cookie_from(@uri, response['set-cookie']) 
    # response = fetch('GET', @uri + response['location'],data) if response.is_a? Net::HTTPRedirection     
    # @rawdoc = response.body
    
    
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

          ##ADD HIDDEN FIELDS TO TRACK VERB, ETC.
          # lnk_node = Nokogiri::XML::Node.new('input', a)
          # lnk_node['type'] = 'hidden'
          # lnk_node['name'] = 'lnk'
          # lnk_node['value'] = formaction
          # a.add_child(lnk_node)
          # 
          # if a['method'].nil? or a['method'].downcase == 'get'
          #   # a.add_child '<input type=hidden name=verb value=get>'
          #   verb_node = Nokogiri::XML::Node.new('input', a)
          #   verb_node['type'] = 'hidden'
          #   verb_node['name'] = 'verb'
          #   verb_node['value'] = 'get'
          #   a.add_child(verb_node)
          # else
          #   a['method'] = 'get'
          #   # a.add_child '<input type=hidden name=verb value=post>'
          #   verb_node = Nokogiri::XML::Node.new('input', a)
          #   verb_node['type'] = 'hidden'
          #   verb_node['name'] = 'verb'
          #   verb_node['value'] = 'post'
          #   a.add_child(verb_node)
          # end

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

    #Hack to remove double wacks in URL ie http://sunsounds.org//audio//programs
    @finaldoc.gsub("://", "/::")
    @finaldoc.gsub("//", "/")
    @finaldoc.gsub("/::", "://")         
    
    #Add baseURL to code within embedded styles
    @finaldoc.gsub("url(/", "url(" + @baseurl)  
    
    #Remove frame breaking javascript
    @finaldoc.gsub(".location.replace", "") 
    

    render :layout => false

  end

end

