ffencoderd
==========

Created by Iago Tomas, and managed as an open source project on github by @jmshelby.

--

###DESCRIPTION
ffencoderd is a daemon that wraps the usage of ffmpeg providing a simple SOAP API to control video encoding jobs. ffencoderd is focused on any video conversion to flash video format although any format accepted by ffmpeg can be used. ffencoderd is divided into two main parts an http server which provides methods to add/retrieve files and request the SOAP api. And a second part the encoder daemon which converts the video. Each part is runned in background as a daemon process.

###INSTALL
Install should be quite straight forward, just by unpackaging and executing the main program file ffencoderd should run. Just be sure to meet all "REQUIREMENTS" found below. There are some scripts in the doc folder of the package which should help in the deployment.

Download latest version,

    "mv ffencoderd-varsion.tar.gz /path/to/install/;cd /path/to/install/"

    "tar -xzvf ffencoderd-version.tar.gz" or "unzip ffencoderd-version.zip"

Edit ffencoderd.conf to meet your system or alternatively create a new config file with needed parameters and pass it with '-c' argument to ffencoderd

Set permissions to defined paths/files in the config file (output.file,video.input.dir,process.dir,video.output.dir,thumbnail.outp ut.dir, log.dir, pid.dir) set to any you want as long as the user executing ffencoderd has read/write privileges.

    "chmod 644 /path/to/output/dir /video/input/dir /process/dir
    /video/output/dir /thumbnail/output/dir /log/dir /pid/dir"

ffencoderd runs under the same user and group that executed it. So beware to not run it with root.

    "/path/to/install/ffencoderd.pl -c /path/to/config/file.conf"

Or run the main program file ffencoderd.pl, it will look for a config file name ffencoderd.conf in the same folder.

    "/path/to/install/ffencoderd.pl"

Just type '-h' to get possible arguments that can be setted. Optionally you can use the init script provided in the doc folder, before you'll need to setup the *FFENCODERD* and *PIDFILE* environment variables or put ffencoderd in the default paths that the scripts looks for. Be carfeul *PIDFILE* must point to the location of the pidfile which is setted in the conf file.

For more information about the configuraion file see the "Configuration File" section.

Once installed and running ( if http config parameter is set to true ) should be possible to access a main page at the address and port defined in the config file, with your web browser. Example http://localhost:8080/ This will show the main page letting you know ffencoderd is succesfully running and gives you some information about it. See the "HTTP Server" section.

Otherwise if you don't want to run ffencoderd HTTP server just set the http config parameter to false, then you may just save your processes in XML in the process.dir directory defined through the config file. This XML processes definition must validate against the DTD definition of ffencoderd. The DTD schema may be found in the ./doc directory or in the main site.

A typical XML process will look like

    <ffencoderd> <process id="0"> <file>filename</file>
    <profile>SomeExistentProfile</profile> <parameter
    name="someName">someValue</parameter> <parameter
    name="someName2">someValue2</parameter> </process> </ffencoderd>

Just create a file and save it in the process.dir, call it somthing.xml.  ffencoderd will parse the file and convert *filename* with default ffmpeg parameters saving the converted file in the video.output.dir directory. ffencoderd SOAP service gots methods to create this files programatically through SOAP, refer to "SOAP" section.

#####Environment variables
These are the environment variables used by the init script provided in the ./doc folder.

######FFENCODERD
The location of the main file program

######PIDFILE
The location of the pidfile created by the ffencoderd daemon, this must be the same as defined in the config file.

######OPTIONS
This variable is optional, you may set any arguments you wish to pass to the start program at init. See "Command Line Arguments" section for more detail.

#####Supported OS
Currently only *UNIX like systems are supported. ffencoderd was developed using an Fedora Core 6 kernel 2.6.18-1.2798.fc6 and perl, v5.8.8 built for i386-linux-thread-multi. Please report on succesful builds on other systems.

###REQUIREMENTS
    ffmpeg
        Tested with FFmpeg version SVN-r8876, Copyright (c) 2000-2007
        Fabrice Bellard, et al.

    perl
        Tested with perl, v5.8.8 built for i386-linux-thread-multi.

#####Perl DEPENDENCIES
    ffencoderd depends on a few cpan perl libraries and ffmpeg. Please refer
    to ffmpeg official site for howto install ffmpeg in your system.

    IPC::ShareLite
    Config::General
    SOAP::Lite (Soap::Transport::HTTP)
    XML::DOM
    XML::Simple
    Pod::WSDL
    Pod::Xhtml
    HTML::Template

    These are libraries that can all be found at CPAN, so just install them
    the way you want. Here is an example of how to install them

    "cpan IPC::ShareLite Config::General SOAP::Lite XML::DOM XML::Simple
    Pod::WSDL Pod::Xhtml HTML::Template"

    Beware that you may need root privileges to install them this way. Look
    at cpan site to install them locally without need to have
    superprivileges.

###Configuration File
    The default configuration filename is ffencoderd.conf which should be
    located at the same folder of the main program file. This is just a
    plain text field with some key value pairs to define config values. Any
    changes in the file will need ffencoderd restart. Next is some
    explanation about.

    http
        Start an http server with different services, otherwise only
        encoding daemon will be started. Possible values are true or false

    host
        The host address for the http server, this is an IP or hostname that
        should resolve to the machine in which ffencoderd is running.

    http.port
        The port which the http should listen to for incoming connections.
        This is any port you like, even though normally we will use an http
        standard port such as 80 if no other web server are running on the
        same machine. If not take any port you like.

    http.spawn.children
        The number of children the http server should create at start to
        listen for incoming connections, this number should depend on your
        system. Don't put a too high number here as it could collapse your
        system. Example : 10

    http.childeren.lifetime
        This is the number of requests each child will attend before dying
        and respawning. Leave it in a high number as 100 or modify if you
        know what you are doing.

    ffmpeg
        The location of ffmpeg in your filesystem. Example : /usr/bin/ffmpeg

    output.file
        This is the file where ffencoderd puts the information about the
        encoded files, in xml format. It must be a full path with filename,
        you may put it wherever you want as long as the the ffencoderd has
        write/read access.

    process.dir
        This is the path to the folder where ffencoderd looks for new file
        processes, is just a writable folder where ffencoderd will look
        and/or put some xml files to configure video conversion processes.
        ffencoderd will scan this directory every delay seconds for *.xml
        process definitions, these are XML files that validate the DTD
        schema given with ffencoderd and that you may found at ffencoderd
        main's site. If the http server is not activated or if you prefer to
        interact directly with the daemon you may save any xml file with
        process definitions in this directory. The daemon will parse and
        delete them after finishing defined processes.

    video.output.dir
        This is the path to a writeable folder where ffencoderd will output
        converted videos.

    video.input.dir
        This is the path to a writeable folder where ffencoderd will look
        for videos to encode.

    show.news
        Set this option to show recent news from the project in the main
        page of the server, possible values are true or false. The news are
        fetched from
        http://sourceforge.net/export/rss2_projnews.php?group_id=218142 .

    log This parameter defines if internal log messages should be logged,
        possible values are true or false.

    log.file
        This is the filename for the log file. Example ffencoderd.log

    log.dir
        This is the path to a writeable folder where the logs will be putted
        in. Example /path/to/install/logs

    pid.dir
        This is the path to a writeable folder where the pidfile will be
        saved to. Example /var/run/ Remark that last slash is needed.

    dtd This is the url of the DTD file that will be added to all
        output.file control files created by ffencoderd. Normally this
        shouldn't be needed to be modified. There's always an updated DTD
        version at ffencoderd site

    Some more explanations may be found in the example config file found in
    the doc folder.

###Profiles file
    The profiles are the way to set up how the ffmpeg command will be made
    up, these are defined in a file found in the data directory named
    profiles.xml. A profile definition has the following elements

    name
        The profile's name, used to reference it.

    ext The extension used by this profile as is produced by the conersion
        command.

    mount
        The mount point where the resources converted with this profile will
        be accessible.

    type
        Media type to be used in this mount point.

    There are also some elements that define the parameters that can be
    defined through the SOAP API, these parameters are divided into two
    types, the parameters that define the resource to be converted and the
    parameters that define the converted resource, infile and outfile
    parameters. Each can have multiple parameter definition and both types
    are optional, although only infile can really be optional as if there
    aren't any outfile parameters defined the conversion command won't do
    anything at all. The parameters are defined with next elements :

    arg The argument used for the ffmpeg command, ex: -f

    name
        The name for this parameter, this will be the name to use to define
        it through the SOAP api, this name has to be unique over infile and
        outfile parameters.

    default
        The default value for this parameter, this element is optional, if
        it isn't defined the parameter will only be defined if the user
        defines it through the SOAP API.

    To see some examples, see the profiles file in the data directory.

###Command Line Arguments
    There are several arguments that may be defined when calling ffencoderd.
    These are

    -h|help|usage
        Shows a help message with all the possible arguments.

    -v|V|version
        Shows version number and copyright information.

    -c <configfile>
        Sets the config file to be used. Use an absolute path to config
        file. Example /path/to/config/file.conf

    -d <delay>
        Sets the delay in seconds to scan for processes. Example 40

    -m <xmlfile>
        Sets the path where the output file will be putted in. Example
        /path/to/output/file.xml

    -p <dirname>
        Sets the path where to look for processes definitions. Example
        /path/to/processes/dir

    -l <logfile>
        Sets the path to the file where to write log messages. Example
        /path/to/log/file.log

    --ffmpeg-output|-fo <ffmpegoutputfile>
        Sets the path to the file where to write ffmpeg encoding output,
        mainly for debugging purposes. Example /path/to/file.log

###HTTP Server
    The HTTP Server of ffencoderd has some paths that may be accesed to
    interact with ffencoderd, next are the explanations for all of them.

    Root path /
        This path will serve the main information screen of ffencoderd with
        some information about the program. You got this documentation, a
        SOAP API reference and a monitor to surveil the ffencoderd server.

    Soap proxy /soap
        This path is the SOAP proxy access. Is where clients should point to
        if not using the WSDL functionality.

    Static path /static/
        This is the path where static files are served from, it won't output
        a file index it will only serve existing files from within the
        ./data/www folder inside the installed path.

    Files path /<source>/*
        Any encoded resource is referenced through the source parameter
        returned by the getProcess method from the SOAP API . To see
        accessible paths see the profiles section and the profiles files to
        see which mount points are setted in your server.

    Upload path /upload
        This path has a double function, it will output an html form example
        if accessed via GET method and will save to the video.input.dir
        parameter folder any multipart file posted to this path via POST
        method. After posting a file the server will output an xml with the
        filename used to save the file, be careful it's not always the same
        filename with which you posted yours a random one may be generated
        if there's already a file with the same name, the extension will be
        always preserved. And the size of the saved file in bytes.

    Stats xml file /stats.xml
        This file is generated each time this is called it outputs an xml
        file with some statistics of the server. It's mainly used for the
        monitor in the main information screen found at /.

    News xml file /news.xml
        This file is the news file used to show news on the main page, if
        you don't want to show news on the main page just use the show.news
        parameter on the config file.

    Processes xml file /processes.xml
        This is the same file that output.file from config, this access is
        for easiness and for monitoring purposes.

###SOAP
    The soap proxy may be accessed through the /soap as specified before,
    even though it can be really accessed via any path that is not
    resolvable to any of listed above.

    An WSDL file definition is accesible through any uri at the server just
    appending ?wsdl, so /soap?wsdl will return the spec file.

    ffencoderd SOAP functionality is based on SOAP-Lite so please refer to
    the module documentation for further information on how the SOAP part
    works.

    You may post any request to the SOAP server conforming the SOAP 1.1
    specification.

    See the API documentation for more information about accesible methods
    on the server.

#####API
    Constants that are returned by the SOAP API

    FFENCODERD_FAIL
        Context : ffencoderd service status functions

        value : 100

    FFENCODERD_OK
        Context : ffencoderd service status functions

        value : 101

    FFENCODERD_UNKNOWN
        Context : ffencoderd encoding processes functions

        value : 200

    FFENCODERD_PROCESSING
        Context : ffencoderd encoding processes functions

        value : 201

    FFENCODERD_SUCCESS
        Context : ffencoderd encoding processes functions

        value : 202

    FFENCODERD_PROBLEM
        Context : ffencoderd encoding processes functions

        value : 203

    The method returns the status of the ffencoderd process. It returns an
    integer value corresponding to an ffencoderd SOAP API constant

    status

     Return
       integer : Constant with the status of the server
       FFENCODERD_OK|FFENCODERD_FAIL. If FFENCODERD_FAIL there is some
       problem with the server

    The method returns an xml with some metadata about the process which has
    been codified

    getProcess

     Parameters
       processId : Identifier for the process, this corresponds to the
       process identifier returned in getList()

     Return
       string : An xml string with some information about the process,
       mainly its characteristics or FFENCODERD_FAIL if didn't find it

    Returns an xml formatted response with a list with uid of ended encoding
    processes

    getList

     Return
       string : An xml string with a list of processes listed by uid

    Add a resource to encode

    addProcess

     Parameters
       process : The process definition as a complex SOAP structure

     Return
       string : Returns a string with a constant indicating if the creation
       of the process was succesful

    Returns the API version

    version

     Return
       string : A string with the API's version

#####Examples
    Next is an example of using SOAP-Lite as client to request version
    number to ffencoderd running in localhost.

            use SOAP::Lite;
            my $soap = SOAP::Lite
           ->proxy('http://localhost:8080/soap')
           ->uri('Service');
            my $invoca = $soap->version();
            my $version = $invoca->result();
            print "ffencoderd v$version";
        
    Or the same in PHP would be something like this.

            <?php
                    $client = new SoapClient("http://localhost:8080/soap?wsdl",array('uri'=>'Service'));
                    echo "ffencoderd v".$client->version()."";
            ?>

###See Also
    You may also find the developers documentation at ffencoderd's website.
    <http://ffencoderd.sourceforge.net>

###COPYRIGHT
            Copyright 2008, Iago Tomas
        
    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation, either version 3 of the License, or (at your
    option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
    Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program. If not, see <http://www.gnu.org/licenses/>.

###AVAILABILITY
    The latest version of this program should be accessible through the main
    ffencoderd site

    http://ffencoderd.sourceforge.net

