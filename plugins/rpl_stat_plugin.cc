/**
   Replication plugin for MySQL.
*/

//#include <stdlib.h>
#include <my_global.h>
#include <mysql/plugin.h>
#include "sql_class.h"                          // THD
#include <hash.h>
#include <replication.h>

#define LOG_LINE_BUFFER_SIZE 80


static struct st_rpl_stat_context
{
  long long counter;         /* event counter, will be modded by 1000 */
  File rpl_stat_log_file;       /* the log file to write to */
} rpl_stat_context;

/**
   Write log
*/
static int write_stat_log(Binlog_transmit_param *param,
                          const char *log_file, my_off_t log_pos)
{
  struct st_rpl_stat_context *context= &rpl_stat_context;
  uint32 server_id= param->server_id;
  char line_buf[LOG_LINE_BUFFER_SIZE];
  
  my_snprintf(line_buf, sizeof(line_buf),
              "server_id:%d, binlog_file:%s, offset:%d\n",
              server_id, log_file, log_pos);
  my_write(context->rpl_stat_log_file, (uchar*) line_buf,
           strlen(line_buf), MYF(0));
  
  DBUG_RETURN(0);
}

/**
   when replication start, write replication position to log immediately
*/
int rpl_stat_transmit_start(Binlog_transmit_param *param,
                            const char *log_file, my_off_t log_pos)
{
  DBUG_RETURN(write_stat_log(param, log_file, log_pos));
}

/**
   when replicating, write replication position to log every 1000 times
*/
int rpl_stat_before_send_event(Binlog_transmit_param *param,
                               unsigned char *packet, unsigned long len,
                               const char *log_file, my_off_t log_pos)
{
  struct st_rpl_stat_context *context= &rpl_stat_context;

  if(context->counter++ % 1000 == 0)
    DBUG_RETURN(write_stat_log(param, log_file, log_pos));

  DBUG_RETURN(0);
}


/**
 * build transmit observer structure
 */
Binlog_transmit_observer transmit_observer = {
  sizeof(Binlog_transmit_observer), // len

  NULL,                             // start
  NULL,                             // stop
  NULL,                             // reserve_header
  rpl_stat_before_send_event,       // before_send_event
  NULL,                             // after_send_event
  NULL,                             // reset
};

/**
   plugin init function
*/
static int rpl_stat_plugin_init(void *p)
{
  DBUG_ENTER("rpl_stat_plugin_init");
  struct st_rpl_stat_context *context= &rpl_stat_context;
  char log_filename[FN_REFLEN];

  struct st_plugin_int *plugin= (struct st_plugin_int *)p;

  context->counter= 0;
  fn_format(log_filename, "rpl-stat", "", ".log",
            MY_REPLACE_EXT | MY_UNPACK_FILENAME);
  context->rpl_stat_log_file= my_open(log_filename, O_RDWR|O_APPEND|O_CREAT,
                                      MYF(0));

  if (register_binlog_transmit_observer(&transmit_observer, p))
  {
    // registration failed
    my_close(context->rpl_stat_log_file, MYF(0));
    my_free(context);
    DBUG_RETURN(1);
  }

  sql_print_information("*plugin %s regisitered", plugin->name.str);
  DBUG_RETURN(0);
}

/**
   plugin de-init function
*/
static int rpl_stat_plugin_deinit(void *p)
{
  DBUG_ENTER("rpl_stat_plugin_deinit");
  struct st_rpl_stat_context *context= &rpl_stat_context;

  my_close(context->rpl_stat_log_file, MYF(0));
  my_free(context);

  if (unregister_binlog_transmit_observer(&transmit_observer, p))
  {
    sql_print_error("unregister_binlog_transmit_observer failed");
    DBUG_RETURN(1);
  }
  
  DBUG_RETURN(0);
}


/**
   build plugin requisites
*/
struct st_mysql_show_var my_status_vars[]= {
  {""},
};

struct Mysql_replication rpl_stat_plugin
{ MYSQL_REPLICATION_INTERFACE_VERSION };


/**
  plugin library descriptor
*/
mysql_declare_plugin(rpl_stat_plugin)
{
  MYSQL_REPLICATION_PLUGIN,
  &rpl_stat_plugin,
  "rpl_stat_plugin",
  "Vincent Gu (lisnaz@gmail.com)",
  "A plugin which will write replication progress info to log file on master",
  PLUGIN_LICENSE_GPL,
  rpl_stat_plugin_init,
  rpl_stat_plugin_deinit,
  0x0100,
  NULL,
  NULL,
  NULL
}
mysql_declare_plugin_end;