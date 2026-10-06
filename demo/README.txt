
a 'var' directory writable by the web server user is needed here (it holds
the session files, do not make it web-accessible), the session dir var/sess
is created inside it on the first request:

  mkdir var
  chmod 1777 var

--