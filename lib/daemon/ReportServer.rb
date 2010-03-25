#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReportServer.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'daemon/ProcessIntercom'
require 'TjException'
require 'Message'

class TaskJuggler

  class ReportServerIface

    include ProcessIntercomIface

    def initialize(server)
      @server = server
    end

    def addFile(authKey, file)
      return false unless @server.checkKey(authKey, 'addFile')

      @server.addFile(file)
    end

    def generateReport(authKey, reportId)
      return false unless @server.checkKey(authKey, 'generateReport')

      @server.generateReport(reportId)
    end

    def checkTimeSheet(authKey, sheet)
      return false unless @server.checkKey(authKey, 'checkTimeSheet')

      @server.checkTimeSheet(sheet)
    end

    def checkStatusSheet(authKey, sheet)
      return false unless @server.checkKey(authKey, 'checkStatusSheet')

      @server.checkStatusSheet(sheet)
    end

  end

  class ReportServer

    include ProcessIntercom

    attr_reader :uri, :authKey

    def initialize(tj)
      initIntercom

      @pid = nil
      @uri = nil

      # A reference to the TaskJuggler object that holds the project data.
      @tj = tj

      # We've started a DRb server before. This will continue to live somewhat
      # in the child. All attempts to create a DRb connection from the child
      # to the parent will end up in the child again. So we use a Pipe to
      # communicate the URI of the child DRb server to the parent. The
      # communication from the parent to the child is not affected by the
      # zombie DRb server in the child process.
      rd, wr = IO.pipe

      if (@pid = fork) == -1
        @log.fatal('ReportServer fork failed')
      elsif @pid.nil?
        # This is the child
        $SAFE = 1
        DRb.install_acl(ACL.new(%w[ deny all
                                    allow localhost ]))
        DRb.start_service
        iFace = ReportServerIface.new(self)
        begin
          uri = DRb.start_service('druby://localhost:0', iFace).uri
          @log.debug("Report server is listening on #{uri}")
        rescue
          @log.fatal("ReportServer can't start DRb: #{$!}")
        end

        # Send the URI of the newly started DRb server to the parent process.
        rd.close
        wr.write uri
        wr.close

        # Start a Thread that waits for the @terminate flag to be set and does
        # other background tasks.
        startTerminator

        # Cleanup the DRb threads
        DRb.thread.join
        @log.debug('Report server terminated')
        exit 0
      else
        Process.detach(@pid)
        # This is the parent
        wr.close
        @uri = rd.read
        rd.close
      end
    end

    def addFile(file)
      begin
        @tj.parseFile(file, 'properties')
      rescue TjException
        return false
      end
      true
    end

    def generateReport(id)
      @log.debug("Generating report #{id}")
      if (ok = @tj.generateReport(id))
        @log.debug("Report #{id} generated")
      else
        @log.error("Report generation of #{id} failed")
      end
      ok
    end

    def checkTimeSheet(sheet)
      @log.debug("Checking time sheet #{sheet}")
      ok = @tj.checkTimeSheet(sheet)
      @log.debug("Time sheet #{sheet} is #{ok ? '' : 'not '}ok")
      ok
    end

    def checkStatusSheet(sheet)
      @log.debug("Checking status sheet #{sheet}")
      ok = @tj.checkStatusSheet(sheet)
      @log.debug("Status sheet #{sheet} is #{ok ? '' : 'not '}ok")
      ok
    end

  end

end
