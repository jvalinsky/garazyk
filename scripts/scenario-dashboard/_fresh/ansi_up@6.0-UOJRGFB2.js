var _=function(e,i){return Object.defineProperty?Object.defineProperty(e,"raw",{value:i}):e.raw=i,e},l;(function(e){e[e.EOS=0]="EOS",e[e.Text=1]="Text",e[e.Incomplete=2]="Incomplete",e[e.ESC=3]="ESC",e[e.Unknown=4]="Unknown",e[e.SGR=5]="SGR",e[e.OSCURL=6]="OSCURL"})(l||(l={}));var p=class{constructor(){this.VERSION="6.0.2",this.setup_palettes(),this._use_classes=!1,this.bold=!1,this.faint=!1,this.italic=!1,this.underline=!1,this.fg=this.bg=null,this._buffer="",this._url_allowlist={http:1,https:1},this._escape_html=!0,this.boldStyle="font-weight:bold",this.faintStyle="opacity:0.7",this.italicStyle="font-style:italic",this.underlineStyle="text-decoration:underline"}set use_classes(e){this._use_classes=e}get use_classes(){return this._use_classes}set url_allowlist(e){this._url_allowlist=e}get url_allowlist(){return this._url_allowlist}set escape_html(e){this._escape_html=e}get escape_html(){return this._escape_html}set boldStyle(e){this._boldStyle=e}get boldStyle(){return this._boldStyle}set faintStyle(e){this._faintStyle=e}get faintStyle(){return this._faintStyle}set italicStyle(e){this._italicStyle=e}get italicStyle(){return this._italicStyle}set underlineStyle(e){this._underlineStyle=e}get underlineStyle(){return this._underlineStyle}setup_palettes(){this.ansi_colors=[[{rgb:[0,0,0],class_name:"ansi-black"},{rgb:[187,0,0],class_name:"ansi-red"},{rgb:[0,187,0],class_name:"ansi-green"},{rgb:[187,187,0],class_name:"ansi-yellow"},{rgb:[0,0,187],class_name:"ansi-blue"},{rgb:[187,0,187],class_name:"ansi-magenta"},{rgb:[0,187,187],class_name:"ansi-cyan"},{rgb:[255,255,255],class_name:"ansi-white"}],[{rgb:[85,85,85],class_name:"ansi-bright-black"},{rgb:[255,85,85],class_name:"ansi-bright-red"},{rgb:[0,255,0],class_name:"ansi-bright-green"},{rgb:[255,255,85],class_name:"ansi-bright-yellow"},{rgb:[85,85,255],class_name:"ansi-bright-blue"},{rgb:[255,85,255],class_name:"ansi-bright-magenta"},{rgb:[85,255,255],class_name:"ansi-bright-cyan"},{rgb:[255,255,255],class_name:"ansi-bright-white"}]],this.palette_256=[],this.ansi_colors.forEach(s=>{s.forEach(t=>{this.palette_256.push(t)})});let e=[0,95,135,175,215,255];for(let s=0;s<6;++s)for(let t=0;t<6;++t)for(let r=0;r<6;++r){let n={rgb:[e[s],e[t],e[r]],class_name:"truecolor"};this.palette_256.push(n)}let i=8;for(let s=0;s<24;++s,i+=10){let t={rgb:[i,i,i],class_name:"truecolor"};this.palette_256.push(t)}}escape_txt_for_html(e){return this._escape_html?e.replace(/[&<>"']/gm,i=>{if(i==="&")return"&amp;";if(i==="<")return"&lt;";if(i===">")return"&gt;";if(i==='"')return"&quot;";if(i==="'")return"&#x27;"}):e}append_buffer(e){var i=this._buffer+e;this._buffer=i}get_next_packet(){var e={kind:l.EOS,text:"",url:""},i=this._buffer.length;if(i==0)return e;var s=this._buffer.indexOf("\x1B");if(s==-1)return e.kind=l.Text,e.text=this._buffer,this._buffer="",e;if(s>0)return e.kind=l.Text,e.text=this._buffer.slice(0,s),this._buffer=this._buffer.slice(s),e;if(s==0){if(i<3)return e.kind=l.Incomplete,e;var t=this._buffer.charAt(1);if(t!="["&&t!="]"&&t!="(")return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e;if(t=="["){this._csi_regex||(this._csi_regex=c(o||(o=_([`
                        ^                           # beginning of line
                                                    #
                                                    # First attempt
                        (?:                         # legal sequence
                          \x1B[                      # CSI
                          ([<-?]?)              # private-mode char
                          ([d;]*)                    # any digits or semicolons
                          ([ -/]?               # an intermediate modifier
                          [@-~])                # the command
                        )
                        |                           # alternate (second attempt)
                        (?:                         # illegal sequence
                          \x1B[                      # CSI
                          [ -~]*                # anything legal
                          ([\0-:])              # anything illegal
                        )
                    `],[`
                        ^                           # beginning of line
                                                    #
                                                    # First attempt
                        (?:                         # legal sequence
                          \\x1b\\[                      # CSI
                          ([\\x3c-\\x3f]?)              # private-mode char
                          ([\\d;]*)                    # any digits or semicolons
                          ([\\x20-\\x2f]?               # an intermediate modifier
                          [\\x40-\\x7e])                # the command
                        )
                        |                           # alternate (second attempt)
                        (?:                         # illegal sequence
                          \\x1b\\[                      # CSI
                          [\\x20-\\x7e]*                # anything legal
                          ([\\x00-\\x1f:])              # anything illegal
                        )
                    `]))));let n=this._buffer.match(this._csi_regex);if(n===null)return e.kind=l.Incomplete,e;if(n[4])return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e;n[1]!=""||n[3]!="m"?e.kind=l.Unknown:e.kind=l.SGR,e.text=n[2];var r=n[0].length;return this._buffer=this._buffer.slice(r),e}else if(t=="]"){if(i<4)return e.kind=l.Incomplete,e;if(this._buffer.charAt(2)!="8"||this._buffer.charAt(3)!=";")return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e;this._osc_st||(this._osc_st=d(g||(g=_([`
                        (?:                         # legal sequence
                          (\x1B\\)                    # ESC                           |                           # alternate
                          (\x07)                      # BEL (what xterm did)
                        )
                        |                           # alternate (second attempt)
                        (                           # illegal sequence
                          [\0-]                 # anything illegal
                          |                           # alternate
                          [\b-]                 # anything illegal
                          |                           # alternate
                          [-]                 # anything illegal
                        )
                    `],[`
                        (?:                         # legal sequence
                          (\\x1b\\\\)                    # ESC \\
                          |                           # alternate
                          (\\x07)                      # BEL (what xterm did)
                        )
                        |                           # alternate (second attempt)
                        (                           # illegal sequence
                          [\\x00-\\x06]                 # anything illegal
                          |                           # alternate
                          [\\x08-\\x1a]                 # anything illegal
                          |                           # alternate
                          [\\x1c-\\x1f]                 # anything illegal
                        )
                    `])))),this._osc_st.lastIndex=0;{let a=this._osc_st.exec(this._buffer);if(a===null)return e.kind=l.Incomplete,e;if(a[3])return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e}{let a=this._osc_st.exec(this._buffer);if(a===null)return e.kind=l.Incomplete,e;if(a[3])return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e}this._osc_regex||(this._osc_regex=c(b||(b=_([`
                        ^                           # beginning of line
                                                    #
                        \x1B]8;                    # OSC Hyperlink
                        [ -:<-~]*       # params (excluding ;)
                        ;                           # end of params
                        ([!-~]{0,512})        # URL capture
                        (?:                         # ST
                          (?:\x1B\\)                  # ESC                           |                           # alternate
                          (?:\x07)                    # BEL (what xterm did)
                        )
                        ([ -~]+)              # TEXT capture
                        \x1B]8;;                   # OSC Hyperlink End
                        (?:                         # ST
                          (?:\x1B\\)                  # ESC                           |                           # alternate
                          (?:\x07)                    # BEL (what xterm did)
                        )
                    `],[`
                        ^                           # beginning of line
                                                    #
                        \\x1b\\]8;                    # OSC Hyperlink
                        [\\x20-\\x3a\\x3c-\\x7e]*       # params (excluding ;)
                        ;                           # end of params
                        ([\\x21-\\x7e]{0,512})        # URL capture
                        (?:                         # ST
                          (?:\\x1b\\\\)                  # ESC \\
                          |                           # alternate
                          (?:\\x07)                    # BEL (what xterm did)
                        )
                        ([\\x20-\\x7e]+)              # TEXT capture
                        \\x1b\\]8;;                   # OSC Hyperlink End
                        (?:                         # ST
                          (?:\\x1b\\\\)                  # ESC \\
                          |                           # alternate
                          (?:\\x07)                    # BEL (what xterm did)
                        )
                    `]))));let n=this._buffer.match(this._osc_regex);if(n===null)return e.kind=l.ESC,e.text=this._buffer.slice(0,1),this._buffer=this._buffer.slice(1),e;e.kind=l.OSCURL,e.url=n[1],e.text=n[2];var r=n[0].length;return this._buffer=this._buffer.slice(r),e}else if(t=="(")return e.kind=l.Unknown,this._buffer=this._buffer.slice(3),e}}ansi_to_html(e){this.append_buffer(e);for(var i=[];;){var s=this.get_next_packet();if(s.kind==l.EOS||s.kind==l.Incomplete)break;s.kind==l.ESC||s.kind==l.Unknown||(s.kind==l.Text?i.push(this.transform_to_html(this.with_state(s))):s.kind==l.SGR?this.process_ansi(s):s.kind==l.OSCURL&&i.push(this.process_hyperlink(s)))}return i.join("")}with_state(e){return{bold:this.bold,faint:this.faint,italic:this.italic,underline:this.underline,fg:this.fg,bg:this.bg,text:e.text}}process_ansi(e){let i=e.text.split(";");for(;i.length>0;){let s=i.shift(),t=parseInt(s,10);if(isNaN(t)||t===0)this.fg=null,this.bg=null,this.bold=!1,this.faint=!1,this.italic=!1,this.underline=!1;else if(t===1)this.bold=!0;else if(t===2)this.faint=!0;else if(t===3)this.italic=!0;else if(t===4)this.underline=!0;else if(t===21)this.bold=!1;else if(t===22)this.faint=!1,this.bold=!1;else if(t===23)this.italic=!1;else if(t===24)this.underline=!1;else if(t===39)this.fg=null;else if(t===49)this.bg=null;else if(t>=30&&t<38)this.fg=this.ansi_colors[0][t-30];else if(t>=40&&t<48)this.bg=this.ansi_colors[0][t-40];else if(t>=90&&t<98)this.fg=this.ansi_colors[1][t-90];else if(t>=100&&t<108)this.bg=this.ansi_colors[1][t-100];else if((t===38||t===48)&&i.length>0){let r=t===38,n=i.shift();if(n==="5"&&i.length>0){let h=parseInt(i.shift(),10);h>=0&&h<=255&&(r?this.fg=this.palette_256[h]:this.bg=this.palette_256[h])}if(n==="2"&&i.length>2){let h=parseInt(i.shift(),10),a=parseInt(i.shift(),10),f=parseInt(i.shift(),10);if(h>=0&&h<=255&&a>=0&&a<=255&&f>=0&&f<=255){let u={rgb:[h,a,f],class_name:"truecolor"};r?this.fg=u:this.bg=u}}}}}transform_to_html(e){let i=e.text;if(i.length===0||(i=this.escape_txt_for_html(i),!e.bold&&!e.italic&&!e.underline&&e.fg===null&&e.bg===null))return i;let s=[],t=[],r=e.fg,n=e.bg;e.bold&&s.push(this._boldStyle),e.faint&&s.push(this._faintStyle),e.italic&&s.push(this._italicStyle),e.underline&&s.push(this._underlineStyle),this._use_classes?(r&&(r.class_name!=="truecolor"?t.push(`${r.class_name}-fg`):s.push(`color:rgb(${r.rgb.join(",")})`)),n&&(n.class_name!=="truecolor"?t.push(`${n.class_name}-bg`):s.push(`background-color:rgb(${n.rgb.join(",")})`))):(r&&s.push(`color:rgb(${r.rgb.join(",")})`),n&&s.push(`background-color:rgb(${n.rgb})`));let h="",a="";return t.length&&(h=` class="${t.join(" ")}"`),s.length&&(a=` style="${s.join(";")}"`),`<span${a}${h}>${i}</span>`}process_hyperlink(e){let i=e.url.split(":");return i.length<1||!this._url_allowlist[i[0]]?"":`<a href="${this.escape_txt_for_html(e.url)}">${this.escape_txt_for_html(e.text)}</a>`}};function c(e,...i){let s=e.raw[0],t=/^\s+|\s+\n|\s*#[\s\S]*?\n|\n/gm,r=s.replace(t,"");return new RegExp(r)}function d(e,...i){let s=e.raw[0],t=/^\s+|\s+\n|\s*#[\s\S]*?\n|\n/gm,r=s.replace(t,"");return new RegExp(r,"g")}var o,g,b;export{p as AnsiUp};
