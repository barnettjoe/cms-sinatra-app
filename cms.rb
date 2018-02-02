require "sinatra"
require "sinatra/contrib"
require "sinatra/reloader" if development?
require "erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "fileutils"

enable :sessions
set :session_secret, 'super secret'

SUPPORTED_EXTENSIONS = %w[.txt .md]
SUPPORTED_IMAGE_EXTENSIONS = %w[.jpg .png .svg]

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

# setup dirs for versioning

def make_version_dir_path(name)
  dir_path = File.join(data_path, "docs", name, "versions")
  FileUtils.mkdir_p(dir_path)
  dir_path
end

def new_version(name)
  File.basename(Tempfile.new(name).path)
end

def record(version, dir_path)
  File.open(File.join(dir_path, "version_paths.txt"), "a") do |file|
    file.puts(version)
  end
end

def create_document(name)
  # setup dirs for versioning
  dir_path = make_version_dir_path(name)
  # make new version and add to list
  version = new_version(name)
  record(version, dir_path)
  # make (empty) first version file
  FileUtils.touch(File.join(dir_path, version))
  session[:flash] = "made new file: #{name}"
end

def valid?(name)
  if !name[/\S+/]
    session[:flash] = "A name is required."
    return false
  elsif SUPPORTED_EXTENSIONS.none? { |ext| name.end_with?(ext) }
    session[:flash] = "file extension must be one of: #{SUPPORTED_EXTENSIONS.join(", ")}"
    return false
  elsif doc_files.include?(name)
    session[:flash] = "a file already exists with that name"
    return false
  end
  true
end

def show(file, file_path)
# need file e.g. hello.md as well as file_path e.g. /data/docs/hello.md872349827349 to get proper extension
  raw = File.read(file_path)
  if File.extname(file) == ".md"
    headers["Content-Type"] = "text/html"
    render_markdown(raw)
  else
    headers["Content-Type"] = "text/plain"
    raw
  end
end

def signed_in?
  session[:user]
end

def signed_in_only
  if signed_in?
    yield
  else
    session[:flash] = "You must be signed in to do that"
    redirect "/"
  end
end

def correct?(stored_hash, password)
  restored_hash = BCrypt::Password.new(stored_hash)
  restored_hash == password
end

helpers do
  def render_markdown(raw)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(raw)
  end

  def doc_files
    doc_pattern = File.join(data_path, "docs", "*")
    Dir.glob(doc_pattern).map { |file| File.basename(file) }
  end
end


get "/" do
  img_pattern = File.join(data_path, "images", "*")
  @img_files = Dir.glob(img_pattern).map { |file| File.basename(file) }

  erb :home
end

get "/users/signin" do
  erb :signin
end

get "/users/signup" do
  erb :signup
end

post '/users/signup' do
  users = load_user_credentials
  username = params[:username]
  if users.keys.include?(username)
    session[:flash] = "sorry, that username is already taken"
    redirect "/users/signup"
  else
    users[username] = BCrypt::Password.create(params[:password])
    File.write(credentials_path, YAML.dump(users))
    session[:flash] = "You have successfully signed up!"
    redirect "/"
  end
end

post "/signin" do
  users = load_user_credentials
  username = params[:username]
  password = params[:password]
  stored_hash = users[username]
  if stored_hash && correct?(stored_hash, password)
    session[:user] = username
    session[:flash] = "Welcome!"
    redirect "/"
  else
    status 422
    session[:flash] = "invalid credentials"
    erb :signin
  end
end

post '/signout' do
  session.delete(:user)
  session[:flash] = "you have been signed out"
  redirect "/"
end

get "/new" do
  signed_in_only do
    erb :new
  end
end

post "/new" do
  signed_in_only do
    doc_name = params[:file_name]
    if valid?(doc_name)
      create_document(doc_name)
      redirect "/"
    else
      status 422
      erb :new
    end
  end
end

get "/upload_image" do
  signed_in_only do
    erb :upload_image
  end
end

post "/upload_image" do
  signed_in_only do
    unless params[:file]
      session[:flash] = "please choose a file"
      redirect "/upload_image"
    end
    tempfile = params[:file][:tempfile]
    filename = params[:file][:filename]
    if SUPPORTED_IMAGE_EXTENSIONS.any? { |ext| filename.end_with?(ext) }
      new_img_path = File.join(data_path, "images", filename)
      File.write(new_img_path, File.read(tempfile.path))
      session[:flash] = "uploaded #{filename}"
      redirect "/"
    else
      status 422
      erb :upload_image
    end
  end
end

def latest_version(file)
  path = File.join(data_path, "docs", file, "versions", "version_paths.txt")
  File.read(path).split.map { |version| File.basename(version) }.last
end

get "/docs/:file" do
  file = params[:file]
  path = File.join(data_path, "docs", file, "versions")

  pattern = File.join(data_path, "docs", "*")
  @files = Dir.glob(pattern).map { |file| File.basename(file) }
  if @files.include? file
    file_path = File.join(path, latest_version(file))
    show(file, file_path)
  else
    session[:flash] = "#{file} does not exist."
    redirect "/"
  end
end

get '/images/:img' do
  @image_location = File.join(data_path, "images", params[:img])
  send_file(@image_location)
end

get "/docs/:file/edit" do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, "docs", file, "versions", latest_version(file))
    @txt = File.read(file_path)
    erb :edit
  end
end

# delete image

post '/images/:file/delete' do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, "images", file)
    File.delete file_path
    session[:flash] = "#{file} was deleted."
    redirect "/"
  end
end

# delete text doc

post '/docs/:file/delete' do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, "docs", file)
    FileUtils.rm_rf file_path
    session[:flash] = "#{file} was deleted."
    redirect "/"
  end
end

get '/docs/:file/duplicate' do
  @doc_name = params[:file]
  signed_in_only do
    erb :duplicate
  end
end

# duplicate text doc

post '/docs/:file/duplicate' do
  signed_in_only do
    @file = params[:file]
    dupe_name = params[:dupe_name]
    if valid?(dupe_name)
      create_document(dupe_name)
      original_file_path = File.join(data_path, "docs", @file, "versions",latest_version(@file))
      content = File.read(original_file_path)
      dupe_path = File.join(data_path, "docs", dupe_name, "versions",latest_version(dupe_name))
      File.write(dupe_path, content)
      redirect "/"
    else
      status 422
      redirect "/docs/#{params[:file]}/duplicate"
    end
  end
end

post '/docs/:file/edit' do
  signed_in_only do
    new_content = params[:content]
    file = params[:file]

    # make new version file

    version = new_version(file)

    # write content to new version file

    File.open(File.join(data_path, "docs", file, "versions", version), "w") do |file|
      file.write(new_content)
    end

    # record version

    record(version, File.join(data_path, "docs", file, "versions"))
    session[:flash] = "#{file} has been updated."
    redirect "/"
  end
end

get '/docs/:file/versions' do
  @file = params[:file]
  @version_path = File.join(data_path, "docs", @file, "versions")
  @versions = File.readlines(File.join(@version_path, "version_paths.txt"))
  erb :versions
end

get "/:file/version/:version_id" do
  @file = params[:file]
  show(@file, File.join(data_path, "docs", @file, "versions", params[:version_id]))
end