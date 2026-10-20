/// <reference types="vite/client" />
declare const __SITE_VERSION__: string;
declare module 'plotly.js-dist-min' {
  import * as Plotly from 'plotly.js';
  export default Plotly;
}
