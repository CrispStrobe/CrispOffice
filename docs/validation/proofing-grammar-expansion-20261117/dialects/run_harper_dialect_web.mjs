import assert from 'node:assert/strict';
import {Worker as NodeWorker} from 'node:worker_threads';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
let created=0,terminated=0;
class BrowserWorker {
  constructor(url) {
    this.listeners=new Map();
    this.worker=new NodeWorker(pathToFileURL(resolve(process.argv[4])),{workerData:{module:url}});
    created++;
    this.worker.on('message',data=>this.dispatch('message',{data}));
    this.worker.on('error',error=>this.dispatch('error',{error}));
  }
  addEventListener(name,listener){const list=this.listeners.get(name)??[];list.push(listener);this.listeners.set(name,list);}
  dispatch(name,event){for(const listener of this.listeners.get(name)??[])listener(event);}
  postMessage(value){this.worker.postMessage(value);}
  terminate(){if(this.stopped)return;this.stopped=true;terminated++;void this.worker.terminate();}
}
globalThis.self=globalThis;
globalThis.Worker=BrowserWorker;
globalThis.qudsHarperWorkerUrl=pathToFileURL(resolve(process.argv[3])).href;
const complete=new Promise(resolve=>{globalThis.qudsHarperSmokeDone=value=>resolve(JSON.parse(value));});
const timer=setTimeout(()=>{console.error('Dialect runtime probe timed out');process.exit(1);},45000);
try{
  await import(pathToFileURL(resolve(process.argv[2])));
  const result=await complete;
  console.log(JSON.stringify({...result,workers_created:created,workers_terminated:terminated},null,2));
  assert.equal(result.status,'passed',JSON.stringify(result.failures));
  assert.equal(result.successful_requests,20);
  assert.equal(result.unsupported_requests,4);
  assert.equal(created,1,'One reused worker');
  assert.equal(terminated,created,'All workers terminated');
}finally{clearTimeout(timer);}
