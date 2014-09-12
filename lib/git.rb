class Application
  GIT_REPOS_PATH = File.realpath(File.join(File.dirname(__FILE__), "..", "repos", "git"))

  # Returns the HEAD object (get_text_file)
  get '/git/:repo/HEAD' do
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    headers "Expires"       => "Fri, 01 Jan 1980 00:00:00 GMT",
            "Pragma"        => "no-cache",
            "Cache-Control" => "no-cache, max-age=0, must-revalidate"

    content_type "text/plain"
    send_file path
  end

  # Returns the refs object (get_info_refs)
  get '/git/:repo/info/refs' do
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    headers "Expires"       => "Fri, 01 Jan 1980 00:00:00 GMT",
            "Pragma"        => "no-cache",
            "Cache-Control" => "no-cache, max-age=0, must-revalidate"

    if params["service"]
      if params["service"].match(/^git-/)
        service = params["service"].gsub(/^git-/, "")
        content_type "application/x-git-#{service}-advertisement"
        case service
        when "upload-pack"
          def packet_write(line)
            (line.size + 4).to_s(base=16).rjust(4, "0") + line
          end

          response.body.clear
          response.body << packet_write("# service=#{params["service"]}\n")
          response.body << "0000"
          response.body << `git upload-pack --stateless-rpc --advertise-refs #{path}`
          response.finish
        else
          status 404
        end
      else
        status 404
      end
    else
      content_type "text/plain"

      path = File.join(path, "info", "refs")

      send_file path
    end
  end

  get '/git/:repo/objects/info/*' do |file|
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    if file == "packs"
      path = File.join(path, "objects", "info", "packs")

      headers "Expires"       => "Fri, 01 Jan 1980 00:00:00 GMT",
              "Pragma"        => "no-cache",
              "Cache-Control" => "no-cache, max-age=0, must-revalidate"

      content_type "text/plain; charset=utf-8"
      send_file path
    elsif file == "alternates" or file == "http-alternates"
      path = File.join(path, "objects", "info", file)

      headers "Expires"       => "Fri, 01 Jan 1980 00:00:00 GMT",
              "Pragma"        => "no-cache",
              "Cache-Control" => "no-cache, max-age=0, must-revalidate"

      content_type "text/plain"
      send_file path
    else
      status 404
    end
  end

  get '/git/:repo/objects/pack/pack-*.*' do |prefix, suffix|
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    # Validate prefix/suffix
    if prefix.match(/^[0-9a-f]{40}$/).nil? or suffix.match(/^pack$|^idx$/).nil?
      status 404
    else
      # Send packed object
      if suffix == "idx"
        content_type "application/x-git-packed-objects-toc"
      else
        content_type "application/x-git-packed-objects"
      end

      path = File.join(path, "objects", "pack", prefix)

      now = Time.now
      headers "Date" => now.to_s,
              "Expires" => (now + 31536000).to_s,
              "Cache-Control" => "public, max-age=31536000"

      send_file path
    end
  end

  get '/git/:repo/objects/*/*' do |prefix, suffix|
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    # Validate prefix/suffix
    if prefix.match(/^[0-9a-f]{2}$/).nil? or suffix.match(/^[0-9a-f]{38}$/).nil?
      status 404
    else
      # Send loose object
      content_type "application/x-git-loose-object"

      path = File.join(path, "objects", prefix, suffix)

      now = Time.now
      headers "Date" => now.to_s,
              "Expires" => (now + 31536000).to_s,
              "Cache-Control" => "public, max-age=31536000"

      send_file path
    end
  end

  post '/git/:repo/:service' do
    path = File.realpath(File.join(GIT_REPOS_PATH, params[:repo]))
    status 404 and return unless path.start_with? GIT_REPOS_PATH

    allowed_services = ["git-upload-pack"]

    if not allowed_services.include? params[:service]
      status 404
    else
      service = params[:service].gsub(/^git-/, "")

      content_type "application/x-git-#{service}-result"

      input = request.body.read
      command = "git #{service} --stateless-rpc #{path}"

      IO.popen(command, File::RDWR) do |pipe|
        pipe.write(input)
        while !pipe.eof?
          block = pipe.read(8192) # 8M at a time
          response.write block # steam it to the client
        end
      end

      response.finish
    end
  end
end
