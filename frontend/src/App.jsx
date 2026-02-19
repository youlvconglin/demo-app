import { useState } from 'react'
import { Upload, Button, message, Card, Progress, Space, Typography } from 'antd'
import { InboxOutlined, FileTextOutlined } from '@ant-design/icons'
import axios from 'axios'
import './App.css'

const { Dragger } = Upload
const { Title, Text } = Typography

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api/v1'

function App() {
  const [file, setFile] = useState(null)
  const [converting, setConverting] = useState(false)
  const [progress, setProgress] = useState(0)
  const [result, setResult] = useState(null)

  // 生成客户端 ID
  const getClientId = () => {
    let clientId = localStorage.getItem('client_id')
    if (!clientId) {
      clientId = 'client_' + Math.random().toString(36).substr(2, 9)
      localStorage.setItem('client_id', clientId)
    }
    return clientId
  }

  // 处理文件上传
  const handleUpload = async (taskType) => {
    if (!file) {
      message.error('请先选择 PDF 文件')
      return
    }

    setConverting(true)
    setProgress(0)
    setResult(null)

    try {
      // 1. 上传文件到服务器
      const formData = new FormData()
      formData.append('file', file)

      const uploadRes = await axios.post(`${API_BASE_URL}/upload`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: (progressEvent) => {
          const percentCompleted = Math.round((progressEvent.loaded * 50) / progressEvent.total)
          setProgress(percentCompleted)
        }
      })

      const fileKey = uploadRes.data.file_key
      setProgress(50)

      // 2. 创建转换任务
      const taskRes = await axios.post(`${API_BASE_URL}/tasks`, {
        file_key: fileKey,
        task_type: taskType,
        file_name: file.name,
        file_size: file.size,
        client_id: getClientId()
      })

      const taskId = taskRes.data.task_id

      // 3. 轮询任务状态
      const pollTask = async () => {
        const statusRes = await axios.get(`${API_BASE_URL}/tasks/${taskId}`)
        const status = statusRes.data.status

        if (status === 'completed') {
          setProgress(100)
          setResult(statusRes.data)
          message.success('转换完成！')
          setConverting(false)
        } else if (status === 'failed') {
          message.error('转换失败: ' + statusRes.data.error_msg)
          setConverting(false)
        } else if (status === 'processing') {
          setProgress(prev => Math.min(prev + 10, 90))
          setTimeout(pollTask, 2000)
        } else {
          setTimeout(pollTask, 2000)
        }
      }

      setTimeout(pollTask, 2000)

    } catch (error) {
      console.error('Upload error:', error)

      if (error.response?.status === 402) {
        message.warning('文件过大，需要付费解锁')
      } else {
        message.error('上传失败: ' + (error.response?.data?.detail || error.message))
      }

      setConverting(false)
    }
  }

  const uploadProps = {
    name: 'file',
    multiple: false,
    accept: '.pdf',
    beforeUpload: (file) => {
      if (file.type !== 'application/pdf') {
        message.error('只支持 PDF 文件')
        return Upload.LIST_IGNORE
      }

      if (file.size > 500 * 1024 * 1024) {
        message.error('文件过大，最大支持 500MB')
        return Upload.LIST_IGNORE
      }

      setFile(file)
      message.success(`已选择: ${file.name}`)
      return false
    }
  }

  return (
    <div className="app">
      <div className="container">
        <Title level={1}>PDFShift</Title>
        <Text type="secondary">在线 PDF 转换工具 - 免费、快速、安全</Text>

        <Card style={{ marginTop: 32 }}>
          <Dragger {...uploadProps} disabled={converting}>
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">点击或拖拽 PDF 文件到此区域</p>
            <p className="ant-upload-hint">
              支持单个文件上传，最大 500MB
            </p>
          </Dragger>

          {file && !converting && !result && (
            <Space style={{ marginTop: 24 }} wrap>
              <Button type="primary" icon={<FileTextOutlined />} onClick={() => handleUpload('pdf2word')}>
                转换为 Word
              </Button>
              <Button icon={<FileTextOutlined />} onClick={() => handleUpload('pdf2excel')}>
                转换为 Excel
              </Button>
              <Button icon={<FileTextOutlined />} onClick={() => handleUpload('pdf2ppt')}>
                转换为 PPT
              </Button>
            </Space>
          )}

          {converting && (
            <div style={{ marginTop: 24 }}>
              <Progress percent={progress} status="active" />
              <Text type="secondary">正在处理中，请稍候...</Text>
            </div>
          )}

          {result && (
            <Card style={{ marginTop: 24 }} type="inner">
              <Title level={4}>转换完成！</Title>
              <Text>文件名: {result.file_name}</Text>
              <br />
              <Button
                type="primary"
                style={{ marginTop: 16 }}
                href={result.download_url}
                download
              >
                下载文件
              </Button>
              <Text type="secondary" style={{ marginLeft: 16 }}>
                文件将在 1 小时后自动删除
              </Text>
            </Card>
          )}
        </Card>

        <div className="footer">
          <Text type="secondary">
            © 2026 PDFShift | <a href="/privacy">隐私政策</a> | <a href="/terms">用户协议</a>
          </Text>
        </div>
      </div>
    </div>
  )
}

export default App
