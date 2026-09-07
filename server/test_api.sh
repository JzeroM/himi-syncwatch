#!/bin/bash

# HimiSync 后端服务测试脚本
# 使用方法: bash test_api.sh

BASE_URL="http://localhost:8080"

echo "=== HimiSync 后端 API 测试 ==="
echo ""

# 1. 健康检查
echo "1. 健康检查"
echo "   GET /health"
curl -s "$BASE_URL/health"
echo ""
echo ""

# 2. 列出房间
echo "2. 列出房间"
echo "   GET /api/rooms"
curl -s "$BASE_URL/api/rooms"
echo ""
echo ""

# 3. 创建房间
echo "3. 创建房间"
echo "   POST /api/rooms"
curl -s -X POST "$BASE_URL/api/rooms" \
  -H "Content-Type: application/json" \
  -d '{
    "mediaItemId": "movie-test-001",
    "mediaItemName": "测试电影 - 星际穿越",
    "mediaItemPosterUrl": "http://example.com/poster.jpg",
    "hostId": "user-001",
    "hostName": "测试用户A"
  }'
echo ""
echo ""

# 4. 创建第二个房间
echo "4. 创建第二个房间"
echo "   POST /api/rooms"
curl -s -X POST "$BASE_URL/api/rooms" \
  -H "Content-Type: application/json" \
  -d '{
    "mediaItemId": "series-test-001",
    "mediaItemName": "测试电视剧 - 权力的游戏",
    "hostId": "user-002",
    "hostName": "测试用户B"
  }'
echo ""
echo ""

# 5. 列出所有房间
echo "5. 列出所有房间"
echo "   GET /api/rooms"
curl -s "$BASE_URL/api/rooms"
echo ""
echo ""

# 6. 加入房间（使用上一步创建的房间 ID）
echo "6. 加入房间"
echo "   POST /api/rooms/<id>/join"
# 先获取房间列表
ROOMS=$(curl -s "$BASE_URL/api/rooms")
FIRST_ROOM_ID=$(echo "$ROOMS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "   房间 ID: $FIRST_ROOM_ID"
curl -s -X POST "$BASE_URL/api/rooms/$FIRST_ROOM_ID/join" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-003",
    "userName": "测试用户C"
  }'
echo ""
echo ""

# 7. 获取房间详情
echo "7. 获取房间详情"
echo "   GET /api/rooms/<id>"
curl -s "$BASE_URL/api/rooms/$FIRST_ROOM_ID"
echo ""
echo ""

# 8. 离开房间
echo "8. 离开房间"
echo "   POST /api/rooms/<id>/leave"
curl -s -X POST "$BASE_URL/api/rooms/$FIRST_ROOM_ID/leave" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-003"
  }'
echo ""
echo ""

# 9. 再次获取房间详情（验证用户已离开）
echo "9. 再次获取房间详情（验证用户已离开）"
echo "   GET /api/rooms/<id>"
curl -s "$BASE_URL/api/rooms/$FIRST_ROOM_ID"
echo ""
echo ""

# 10. 删除房间
echo "10. 删除房间"
echo "    DELETE /api/rooms/<id>"
curl -s -X DELETE "$BASE_URL/api/rooms/$FIRST_ROOM_ID"
echo ""
echo ""

# 11. 验证房间已删除
echo "11. 验证房间已删除"
echo "    GET /api/rooms"
curl -s "$BASE_URL/api/rooms"
echo ""
echo ""

echo "=== 测试完成 ==="
