<template>
  <div class="back-layout">
    <div id="userLayout" :class="['user-layout-wrapper', device]">
      <div class="container">
        <div class="poster-img">
          <img src="/static/rightImg.jpg">
        </div>
        <div class="right-form">
          <div class="top">
            <div class="header">
              <a-row>
                <a-col>
                  <a href="/" class="brand">
                    <img class="brand-logo" src="/static/logo.png" alt="思雨食品"/>
                    <span class="title">{{ systemTitle }}</span>
                    <small class="desc">V3.6™</small>
                  </a>
                </a-col>
              </a-row>
            </div>
          </div>
          <route-view></route-view>
        </div>
      </div>
    </div>
    <div class="footer" v-if="device === 'desktop'">
      <p>
        © 2015-2030 思雨食品 ERP · ® 石门思雨食品有限公司 版权所有
      </p>
    </div>
  </div>
</template>

<script>
  import RouteView from "@/components/layouts/RouteView"
  import { mixinDevice } from '@/utils/mixin.js'

  export default {
    name: "UserLayout",
    components: { RouteView },
    mixins: [mixinDevice],
    data () {
      return {
        systemTitle: window.SYS_TITLE,
        systemUrl: window.SYS_URL,
        isShowRight: false,
        isAndroidShow: false,
        isIphoneShow: false,
        isMiniProgramShow: false,
      }
    },
    mounted () {
      document.body.classList.add('userLayout')
    },
    beforeDestroy () {
      document.body.classList.remove('userLayout')
    },
    created () {
      this.isShowRight = false
    },
    methods: {
      handleAndroidCancel() {
        this.isAndroidShow = false
      },
      handleIphoneCancel() {
        this.isIphoneShow = false
      },
      handleMiniProgramCancel() {
        this.isMiniProgramShow = false
      },
      openAndroid() {
        this.isAndroidShow = true
      },
      openIPhone() {
        this.isIphoneShow = true
      },
      openMiniProgram() {
        this.isMiniProgramShow = true
      }
    }
  }
</script>

<style scoped>
  .back-layout {
    width: 100%;
    height: 100%;
    background-image: url(/static/rightImg.jpg);
    background-size: cover;
    background-position: 0 50%;
    background-repeat: no-repeat;
    position: relative;
    overflow: hidden;
  }

  @media (max-width: 767px) {
    .back-layout {
      background-image: url(/static/rightImg.jpg);
      background-position: center top;
      overflow-y: auto;
      overflow-x: hidden;
    }
  }
  .brand {
    display: inline-flex;
    align-items: center;
  }

  .brand-logo {
    width: 34px;
    height: 34px;
    margin-right: 8px;
    vertical-align: middle;
    filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.12));
  }

  #userLayout.user-layout-wrapper.mobile {
    position: static;
    left: auto;
    top: auto;
    margin-left: 0px;
    height: auto;
    padding: 16px 0 32px;
  }
  .third-party-platform {
    display: flex;
    flex-direction: row;
    justify-content: center;
    margin-bottom:15px;
    opacity:0.7
  }
  .third-party-platform .platform-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    cursor: pointer;
    color:#1890ff
  }
  .platform-modal {
    padding:20px;
    margin:20px 50px;
    border:1px solid #eee;
  }
</style>
<style lang="less" scoped>
  #userLayout.user-layout-wrapper {
    position: fixed;
    left: 68%;
    top: 12%;
    margin-left: -170px;
    height: 100%;

    &.mobile {
      .container {
        height: auto;

        .main {
          max-width: 368px;
          width: 98%;
        }

        .right-form {
          width: 94%;
          max-width: 340px;
          height: auto;
          min-height: 460px;
          overflow: visible;
          margin: 24px auto 0;
          padding-bottom: 18px;

          .top .header {
            margin-top: 15px;
            margin-bottom: 20px;
          }
        }
      }
      .poster-img {
        display: none;
      }
    }

    .container {
      float: left;
      width: 100%;
      z-index: 99;
      height: 70%;

      .poster-img {
        display: none;
        float: left;
        height: 100%;
      }

      .right-form {
        background-size: 100%;
        position: relative;
        width: 340px;
        height: 460px;
        background: rgba(255, 255, 255, 1);
        border-radius: 8px;
        right: 0;
        top: 0;
        padding: 10px 30px 0 30px;
        margin-top: 50px;
        -webkit-box-shadow: 0 2px 6px 0 rgb(200 200 200);
        box-shadow: 0 2px 6px 0 rgb(200 200 200);
        overflow: hidden;

        a {
          text-decoration: none;
        }

        .top {
          text-align: center;

          .header {
            height: 44px;
            line-height: 44px;
            margin-top: 35px;
            margin-bottom: 35px;
            .title {
              font-size: 35px;
              color: #666;
              font-family: "Chinese Quote", -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
              font-weight: 700;
              position: relative;
              top: 2px;
              white-space: nowrap;
            }
            .desc {
              font-size: 16px;
              color: #666;
              margin-top: 12px;
              margin-left: 10px;
              margin-bottom: 40px;
            }
          }
        }

        .main {
          min-width: 260px;
          width: 280px;
          margin: 0 auto;
        }
      }
    }
  }
  .footer {
    position: absolute;
    bottom: 14px;
    padding: 0 16px;
    margin: 0;
    text-align: center;
    left: 33%;
    right: 33%;
    z-index: 5;

    p {
      display: inline-block;
      margin: 0;
      padding: 5px 14px;
      border-radius: 16px;
      background: rgba(255, 255, 255, 0.76);
      color: #35506b;
      font-size: 13px;
      line-height: 20px;
      box-shadow: 0 2px 10px rgba(31, 57, 83, 0.08);
      backdrop-filter: blur(4px);
    }

    .links {
      margin-bottom: 8px;
      font-size: 14px;
      a {
        color: rgba(0, 0, 0, 0.45);
        transition: all 0.3s;
        &:not(:last-child) {
          margin-right: 40px;
        }
      }
    }
    .copyright {
      color: rgba(0, 0, 0, 0.45);
      font-size: 14px;
    }
  }
</style>