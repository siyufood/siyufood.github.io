import Vue from 'vue'
import axios from 'axios'
import store from '@/store'
import { VueAxios } from './axios'
import {Modal, notification} from 'ant-design-vue'
import { ACCESS_TOKEN } from "@/store/mutation-types"

/**
 * 【指定 axios的 baseURL】
 * 如果手工指定 baseURL: '/jshERP-boot'
 * 则映射后端域名，通过 vue.config.js
 * @type {*|string}
 */
let apiBaseUrl = window._CONFIG['domianURL'] || "/jshERP-boot";
//console.log("apiBaseUrl= ",apiBaseUrl)
// 创建 axios 实例
const service = axios.create({
  baseURL: apiBaseUrl, // api base_url
  timeout: 300000, // 请求超时时间
  // ngrok 免费版会对浏览器发起的请求插入 warning 拦截页（返回 HTML 而非 JSON），
  // 带上该头即可跳过；deploy/caddy/Caddyfile 已放行此请求头。
  headers: {
    'ngrok-skip-browser-warning': 'true'
  }
})

const err = (error) => {
  if (error.response) {
    let data = error.response.data
    const token = Vue.ls.get(ACCESS_TOKEN)
    switch (error.response.status) {
      case 403:
        notification.error({ message: '系统提示', description: '拒绝访问',duration: 4})
        break
      case 500:
        if(token && data==="loginOut"){
          Modal.error({
            title: '登录已过期',
            content: '很抱歉，登录已过期，请重新登录',
            okText: '重新登录',
            mask: false,
            onOk: () => {
              Vue.ls.remove(ACCESS_TOKEN)
              window.location.reload()
            }
          })
        }
        break
      case 404:
          notification.error({ message: '系统提示', description:'很抱歉，资源未找到!',duration: 4})
        break
      case 504:
        notification.error({ message: '系统提示', description: '网络超时'})
        break
      case 401:
        notification.error({ message: '系统提示', description:'未授权，请重新登录',duration: 4})
        if (token) {
          store.dispatch('Logout').then(() => {
            setTimeout(() => {
              window.location.reload()
            }, 1500)
          })
        }
        break
      default:
        notification.error({
          message: '系统提示',
          description: data.message,
          duration: 4
        })
        break
    }
  }
  return Promise.reject(error)
};

// 免费 ngrok 会给浏览器请求插入确认页；带上这个头可让 API 请求直达后端。
const isNgrokTunnel = /ngrok/i.test(apiBaseUrl)

// request interceptor
service.interceptors.request.use(config => {
  const token = Vue.ls.get(ACCESS_TOKEN)
  if (token) {
    config.headers[ 'X-Access-Token' ] = token // 让每个请求携带自定义 token 请根据实际情况自行修改
  }
  if (isNgrokTunnel) {
    config.headers['ngrok-skip-browser-warning'] = 'true'
  }
  return config
},(error) => {
  return Promise.reject(error)
})

// response interceptor
service.interceptors.response.use((response) => {
    return response.data
  }, err)

// 启动自检：确认运行时接口地址真的可达。
// 页面能打开、接口却报「资源未找到」，绝大多数是 config.js 被浏览器缓存成了旧的穿透域名，
// 这里提前给出明确提示，而不是让用户面对满屏的 404 通知。
const probeBackend = () => {
  if (!/^https?:\/\//i.test(apiBaseUrl)) return // 同源部署（/jshERP-boot）无需自检
  axios.get(apiBaseUrl + '/platformConfig/getPlatform/name', {
    timeout: 8000,
    headers: isNgrokTunnel ? { 'ngrok-skip-browser-warning': 'true' } : {}
  }).catch((error) => {
    const status = error.response ? error.response.status : 0
    if (status === 0 || status === 404) {
      Modal.error({
        title: '后端接口未连通',
        content: '当前页面使用的接口地址 ' + apiBaseUrl + ' 访问失败（HTTP ' + (status || '网络错误') +
          '）。通常是公网穿透域名已变更或后端服务未启动，请按 Ctrl+F5 强制刷新后重试。',
        okText: '刷新页面',
        onOk: () => { window.location.reload() }
      })
    }
  })
}
probeBackend()

const installer = {
  vm: {},
  install (Vue, router = {}) {
    Vue.use(VueAxios, router, service)
  }
}

export {
  installer as VueAxios,
  service as axios
}