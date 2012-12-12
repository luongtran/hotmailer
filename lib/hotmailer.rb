require 'rubygems'
require 'mechanize'


class Hotmailer < Mechanize

attr_accessor :username, :passwd
attr_reader :inbox, :logged_in

def initialize(username,passwd)
  super()
  self.user_agent_alias  = "Windows IE 6"
  @username = username
  @passwd = passwd 
  @inbox = ''
  @contacts = []
  @messages = []
end

def login
#Logs in the user
  first_page = self.get('http://hotmail.com')
  login_form = first_page.form('f1')
  login_form.login = self.username
  login_form.passwd = self.passwd

  login_page = self.submit(login_form)
 
  if login_page.body  =~ /window\.location\.replace\(\"([^"]+)\"/ 
      new_loc = $1
  else
    raise "Error logging in - check username and password and try again"
  end

  main_page = self.get(new_loc)
  
  if main_page.body =~  /_UM\s*=\s*"([^"]+)";?/
    @inbox = $1
  else
    raise "Error getting mailbox - hotmail format may have changed! (Please try logging in manually using your web browser, then retry this)."
  end

  @logged_in = true

end

def contacts(reload=false)
#Get user's contact list (returns an array of hashes, each has a record for one
# user, and contains :name and :email keys)

  unless reload
    return @contacts unless @contacts.empty?
  end

  self.login unless self.logged_in

  #The URL to use to get contacts in printable view
  contacts_url = "/cgi-bin/addresses?fti=yes&PrintView=1&"+self.inbox
  
  all_contacts = self.get(contacts_url)

  #Get separate contacts [those within trs within trs]
  scontacts = all_contacts/"tr/tr"
  
  scontacts.each do |c|
    #Get each contact's name and email, and append it to @contacts 
    details = (c/"td")
    name = details[0].inner_html
    email = ""
    #Sometimes print view does not have an email
    #this checks whether it exists
    if (details[1]/"span")[0]
      email = (details[1]/"span")[0].inner_html
    end
    @contacts << {:name => name,:email => email}
  end

  return @contacts

end

def compose(to,subject,body)
 #Sends an email

 self.login unless self.logged_in
 
 compose_url ="/cgi-bin/compose?"+self.inbox
 comp_page = self.get(compose_url)

 comp_form = comp_page.form("composeform")
 comp_form.to = to
 comp_form.subject = subject
 comp_form.body = body

 res_page = self.submit(comp_form)
 
 unless res_page.body =~ /Your message has been sent/
   raise "There was an error sending the message"
 end

 return true

end

def messages(reload=false)

  unless reload
    return @messages unless @messages.empty?
  end

  self.login unless self.logged_in
  
  page = 1
  last_page = 1
  raw_messages = []
  messages = []

  while page <= last_page.to_i
    msg_url = "/cgi-bin/HoTMaiL?&Sort=rDate&page=#{page}&"+self.inbox
    msg_page = self.get(msg_url)
    
    #Get last page
    lastp = (msg_page/"a[@title='Last Page']")[0]
    if lastp
      lastp.attributes['href'] =~ /HM\('page=(\d+)/
      last_page = $1
    end
   
    msgs = msg_page/"tr[@name]"
    raw_messages += msgs
    
    page+=1
  end

  for msg in raw_messages
    fname = (msg/"a")[0].inner_html
    femail = msg.attributes['name']
    status = (msg/"img")[0].attributes['alt']

    mlink = (msg/"a")[0].attributes['href']
    mlink =~ /G\('([^']+)'/
    mlink = $1
    
    subject = (msg/"td")[6].inner_html
    date = (msg/"td")[7].inner_html
    size = (msg/"td")[8].inner_html
 
    m = Hotmailer::Message.new(self,:from_name=> fname, :from_email => femail, :status => status, :link => mlink, :subject => subject, :date => date, :size => size)

    messages << m
  end

  @messages = messages
  return @messages
end

def add_contact(quickname,email,fname='',lname='')
#To add a contact

  self.login unless self.logged_in
  
  main_url = '/cgi-bin/hmhome?'+self.inbox
  main_page = self.get(main_url)

  c_link =  (main_page/"a[@href=#]").find {|c| c.inner_html == "New Contact"}
  unless c_link['onclick'] =~ /G\('([^']+)'/
    raise "Error adding contact - hotmail format may have changed"
  end

  c_href = $1
  contact_page = self.get(c_href+"&"+self.inbox)
  contact_form = contact_page.form('addr')
  
  contact_form.alias = quickname
  contact_form.addrlist = email

  contact_form.aliasfname = fname
  contact_form.aliaslname = lname

  res_page = self.submit(contact_form)

  unless res_page.body =~ /Contact/
    raise "Error adding contact"
  end

  return true
end

end


class Hotmailer::Message
  attr_reader :from_email, :from_name, :status, :link, :subject, :date, :size, :parent, :id


  def initialize(parent,opts = {})
    @from_email = opts[:from_email]
    @from_name = opts[:from_name]
    @status = opts[:status]
    @link = opts[:link]
    @subject = opts[:subject]
    @date = opts[:date]
    @size = opts[:size]
    @body = ''
    @parent = parent
    #Get message id
    @link =~ /msg=(.+)/
    @id = $1
  end

  def read
   #Used to read the message's contents (in plain text)
    return @body unless @body.empty?

    msg_link = self.link+"&raw=0&"+@parent.inbox
    msg_page = @parent.get(msg_link)
    raw_text = (msg_page/"pre")[0].inner_html
    
    if raw_text =~ /\n\n(.+)/m
      msg_text = $1
     else
      msg_text = ''
    end
    
    @body = msg_text
    return @body
  end

  alias :body :read

  def delete
  #Used to delete the message
    #Get message page, and all links on page
    msg_page = parent.get(self.link)
    links = (msg_page/"a")

    #Get delete link
    del_a = links.find {|a| a.inner_html == 'Delete' }
    if del_a.attributes['onclick'] =~ /G\('([^']+)'/
      del_link = $1
    else
      raise "Could not find delete link - hotmail layout changed?"
    end
    
    res_page = parent.get(del_link)
    #Remove self from parent's messages array
    parent.messages.delete(self)
    return true if res_page.body =~ /Mail/

  end

  def forward(to)
    #Forward this message
    f_url = "/cgi-bin/compose?type=f&msg=#{self.id}&"+parent.inbox
    f_page = parent.get(f_url)

    fwd_form = f_page.form('composeform')
    fwd_form.to = to
    res_page = parent.submit(fwd_form)
    
    if res_page.body =~ /Your message has been sent/
      return true
    else
      raise "Error forwarding message"
    end

   end
end
